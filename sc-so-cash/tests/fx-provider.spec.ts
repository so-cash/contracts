import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  ZeroAddress,
  cleanStructAndMap,
  createAutonomousWallet,
  ganacheProvider,
  getLogs,
  getNewWallet,
  recoverSigner,
  setMochaTimeout,
  signHash,
  toBuffer,
} from "@so-cash/sc-shared/utils";
import {
  createAndRegisterNostro,
  createStablecoin,
  declareBank,
  declareReferentials,
  initContractCompilation,
  registerERC20Nostro,
  setCorrespondent,
  unsubscribeAll,
} from "./so-cash-prepare";
import {
  bankIdentifier,
  blockTimestamp,
  contractsNames,
  createAccount,
  receipientInfo,
} from "@so-cash/sc-shared";

import socashContracts from "../build";
import { SmartContractInstance } from "@saturn-chain/smart-contract";
import { EthProviderInterface } from "@saturn-chain/dlt-tx-data-functions";

describe("Test SoCash FX Provider", async function () {
  setMochaTimeout(this, 20_000);
  const web3 = new Web3(ganacheProvider() as any);
  let ref: Awaited<ReturnType<typeof declareReferentials>>;

  this.beforeEach(async () => {
    initContractCompilation(true);
    ref = await declareReferentials(web3, true, "FR", "US");
  });
  this.afterEach(() => {
    unsubscribeAll();
  });

  it("should deploy the FX Provider", async () => {
    const contract = socashContracts.get(contractsNames.cash.fxProvider);
    const owner = await getNewWallet(web3, "FxProviderOwner", true);
    const wallet = createAutonomousWallet(web3, "Signatory");

    const instance = await contract.deploy(
      owner.newi(),
      ref.root.deployedAt,
      wallet.address,
    );

    // set the fx rate source
    await instance.setFXRateSource(
      owner.send(),
      toBuffer("xxx"),
      toBuffer("xxx"),
      "https://the.server.com/api/fx/rate",
    );

    const source = await instance.getFXRateSource(
      owner.call(),
      toBuffer("EUR"),
      toBuffer("USD"),
    );
    console.log("FX Rate Source calculated as ", source);

    expect(instance).to.be.not.null;
  });

  it("should sign FX Rate structure and validate the signature on-chain", async () => {
    const contract = socashContracts.get(contractsNames.cash.fxProvider);
    const owner = await getNewWallet(web3, "FxProviderOwner", true);
    const signerWallet = createAutonomousWallet(web3, "Signatory");
    console.log(`Signatory private key: ${signerWallet.privateKey}`);

    const instance = await contract.deploy(
      owner.newi(),
      ref.root.deployedAt,
      signerWallet.address,
    );

    // get the hash of a FX Rate structure
    const blockTs = await blockTimestamp();
    const fxRate = {
      rate: 1.1 * 10_000,
      rateTime: blockTs,
      expiryTime: blockTs + 60, // 10 seconds later
      base: toBuffer("EUR"),
      quote: toBuffer("USD"),
    };

    const hash = await instance.hashOfFXRate(owner.call(), fxRate);
    console.log(`hash: ${hash}`);

    // sign the hash with the signer wallet
    const signature = signHash(hash, signerWallet);
    console.log(`signature: ${signature}`, signature.length / 2);

    // verify the signature off-chain
    const recovered = recoverSigner(hash, signature);
    console.log(`recovered: ${recovered}`);
    expect(recovered).to.be.equal(signerWallet.address);

    // validate the signature on-chain
    const valid = await instance.verifyFXRate(owner.call(), fxRate, signature);
    expect(valid).to.be.true;
  });

  async function createAndSignFxRate(
    signer: ReturnType<typeof createAutonomousWallet>,
    fxProvider: SmartContractInstance,
    intf: EthProviderInterface,
    base: string,
    quote: string,
    price: number,
    duration: number = 60,
  ) {
    const blockTs = await blockTimestamp();
    console.log(`blockTs for price: ${blockTs}`, "duration", duration);

    const fxRate = {
      rate: price * 10_000,
      rateTime: blockTs,
      expiryTime: blockTs + duration,
      base: toBuffer(base),
      quote: toBuffer(quote),
    };

    const hash = await fxProvider.hashOfFXRate(intf.call(), fxRate);
    const signature = signHash(hash, signer);
    return { fxRate, signature };
  }

  it("should settle a FX operation", async () => {
    // create 2 banks in 2 different currencies EUR and USD
    const bankEUR = await declareBank(
      web3,
      ref,
      "AGRIFRPP",
      bankIdentifier("FR", ["10000", "11111"]),
      "EUR",
      2,
      true,
    );
    const bankUSD = await declareBank(
      web3,
      ref,
      "BOFAUS3N",
      bankIdentifier("US", ["20000", "22222"]),
      "USD",
      2,
      true,
    );

    // create a FX provider
    const contract = socashContracts.get(contractsNames.cash.fxProvider);
    const owner = await getNewWallet(web3, "FxProviderOwner", true);
    const signer = createAutonomousWallet(web3, "Signatory");

    const instance = await contract.deploy(
      owner.newi(),
      ref.root.deployedAt,
      signer.address,
    );

    // publish the FX Provider in the Referential (FR)
    await ref.countries["FR"].setFXProvider(
      bankEUR.boUser.send(),
      bankEUR.id.codes[0],
      instance.deployedAt,
    );

    // create the accounts for the FxProvider in each of the banks
    const accountEUR = await createAccount(
      "FxProviderEUR",
      bankEUR.bank,
      bankEUR.boUser,
    );
    const accountUSD = await createAccount(
      "FxProviderUSD",
      bankUSD.bank,
      bankUSD.boUser,
    );

    // create 2 client accounts in each of the banks
    const clientEUR = await createAccount(
      "ClientEUR",
      bankEUR.bank,
      bankEUR.boUser,
    );
    const clientUSD = await createAccount(
      "ClientUSD",
      bankUSD.bank,
      bankUSD.boUser,
    );

    // register the fx provider accounts in the smart contract
    await instance.setCurrencyAccount(
      owner.send(),
      toBuffer("EUR"),
      accountEUR.deployedAt,
    );
    await instance.setCurrencyAccount(
      owner.send(),
      toBuffer("USD"),
      accountUSD.deployedAt,
    );
    // allow the FX Provider smart contract to operate its accounts
    await accountEUR.whitelist(bankEUR.boUser.send(), instance.deployedAt);
    await accountUSD.whitelist(bankUSD.boUser.send(), instance.deployedAt);

    // credit the account EUR of the client
    await bankEUR.bank.credit(
      bankEUR.boUser.send(),
      clientEUR.deployedAt,
      100_000_00,
      "Initial deposit",
    );
    // credit the USD account of the fx provider
    await bankUSD.bank.credit(
      bankUSD.boUser.send(),
      accountUSD.deployedAt,
      1_000_000_00,
      "Initial deposit",
    );

    // Here we assume that we do not know the instance of the FX Provider
    // So we get it from the Referential using the events
    // We assume that the end user is the BO of the EUR bank
    const events = await getLogs(
      ref.countries["FR"].events.FXProviderSet(bankEUR.boUser.get(), {}),
    );
    expect(events.length).to.be.greaterThan(0);
    const fxProviderAddress = events[0].returnValues.fxProvider;
    const fxProvider = contract.at(fxProviderAddress);

    // create a FX rate between EUR and USD
    const { fxRate, signature } = await createAndSignFxRate(
      signer,
      instance,
      bankEUR.boUser,
      "EUR",
      "USD",
      1.1,
      120_00, // 200 minutes because when all tests are run in // there is a time gap that makes it fails
    );

    // Client allows the FX Provider to debit its account
    await clientEUR.approve(
      bankEUR.boUser.send(),
      fxProvider.deployedAt,
      50_000_00,
    );

    // Execute the FX settlement
    await fxProvider.settlement(
      bankEUR.boUser.send(), // can only be called by who created the hash AND an operator allowed on the source account
      receipientInfo(clientEUR.deployedAt),
      receipientInfo(clientUSD.deployedAt),
      50_000_00,
      fxRate,
      signature,
      "FX operation",
    );
    console.log(
      "last block timestamp",
      await blockTimestamp(),
      "rate expiry:",
      fxRate.expiryTime,
    );
  });
});
