import { sha256 } from "js-sha256";
import crypto from "crypto";
import SaturnPkg, {
  type SmartContracts,
  type SmartContractInstance,
} from "@saturn-chain/smart-contract";
const { SmartContracts: SmartContractsClass } = SaturnPkg;
import { EthProviderInterface } from "@saturn-chain/dlt-tx-data-functions";
import { blockTimestamp } from "./dates";
import { ZeroAddress, executioner, map, toBuffer } from "./utils";
import { CombinedFile, Diamond } from "@fever-tokens/diamond/ts-lib";

export const contractsNames = {
  cash: {
    bank: "SoCashBank",
    account: "SoCashAccount",
    fxProvider: "SoCashFXProvider",
    ibanCalc: "IBANCalculator",
    paymentEngine: "PaymentEngine",
    sharedFunctions: "SharedFunctions",
  },
  cashdiamond: {
    account: {
      intf: "ISoCashAccountFull",
      base: "SoCashAccountDiamond",
      readable: "SoCashAccountDiamondReadable",
      writable: "SoCashAccountDiamondWritable",
      // facets
      whitelist: "WhitelistedSenders",
      data: "AccountData",
      htlc: "HTLCPayment",
      actions: "AccountActions",
    },
    bank: {
      intf: "ISoCashBankFull",
      base: "SoCashBankDiamond",
      readable: "SoCashBankDiamondReadable",
      writable: "SoCashBankDiamondWritable",
      // facets
      identity: "BankIdentity",
      whitelist: "WhitelistedSenders",
      boService: "BankBackOfficeServices",
      extService: "BankExternalServices",
      boPayment: "BankBOPayment",
      extPayment: "BankExtPayment",
      iban: "IBANServiceFacet",
      simulation: "BankPaymentSimulation",
    },
    fxprovider: {
      intf: "ISoCashFXProviderFull",
      base: "SoCashFXProviderDiamond",
      readable: "SoCashFXProviderDiamondReadable",
      writable: "SoCashFXProviderDiamondWritable",
      identity: "BankIdentity",
      whitelist: "WhitelistedSenders",
      fxprovider: "FXProvider",
    },
  },
  amm: {
    amm: "CPAMM",
    iBank: "ISoCashBank",
    iAccount: "ISoCashOwnedAccount",
  },
  ref: {
    root: "RootReferential",
    country: "CountryReferential",
    stablecoin: "Stablecoin",
  },
  refdiamond: {
    root: {
      intf: "ISoCashGlobalReferential",
      base: "GlobalReferentialDiamond",
      readable: "GlobalReferentialDiamondReadable",
      writable: "GlobalReferentialDiamondWritable",
      // facets
      finder: "PathFinder",
      countryManager: "CountryManager",
    },
    country: {
      intf: "ISoCashCountryReferential",
      base: "CountryReferentialDiamond",
      readable: "CountryReferentialDiamondReadable",
      writable: "CountryReferentialDiamondWritable",
      // facets
      bankController: "BankController",
      countryState: "CountryStateManagement",
    },
  },
  oppenzeppelin: {
    ownable: "Ownable",
  },
  cashPooling: {
    cashPool: "SoCashPooling",
  },
};

export type ContractNamesType = { [key: string]: string | ContractNamesType };

export function checkContractCompilation(
  contracts: SmartContracts,
  contractsNames: ContractNamesType,
) {
  for (const contractName of Object.values(contractsNames)) {
    if (typeof contractName === "object") {
      checkContractCompilation(contracts, contractName);
    } else if (!contracts.get(contractName)) {
      throw new Error(`Contract ${contractName} not found`);
    } else {
      // console.log(`Contract ${contractName} found`);
    }
  }
}

let __combinedJson: CombinedFile | undefined = undefined;
let __smartContractsLoaded: SmartContracts | undefined = undefined;
export function setSoCashCombinedJson(combinedJson: CombinedFile) {
  __combinedJson = combinedJson;
  __smartContractsLoaded = SmartContractsClass.load(__combinedJson);
}
function getSoCashCombinedJson() {
  if (!__combinedJson) {
    throw new Error("Combined JSON not initialized");
  }
  return __combinedJson;
}
function getSoCashContracts() {
  if (!__smartContractsLoaded) {
    throw new Error("Smart Contracts not initialized");
  }
  return __smartContractsLoaded;
}

export async function createRootReferential(
  contracts: SmartContracts,
  owner: EthProviderInterface,
): Promise<SmartContractInstance> {
  const rootContract = contracts.get(contractsNames.refdiamond.root.intf);
  const rootDiamond = new Diamond(
    {
      combinedJson: contracts.combined,
      rootName: contractsNames.refdiamond.root.base,
      readableName: contractsNames.refdiamond.root.readable,
      writableName: contractsNames.refdiamond.root.writable,
      facetNames: [
        contractsNames.refdiamond.root.finder,
        contractsNames.refdiamond.root.countryManager,
      ],
      initializeFunctionName: "initialize",
      initializeFunctionArgs: [],
    },
    executioner(contracts, owner),
  );
  const rootDeployed = await rootDiamond.deploy();
  const root = rootContract.at(rootDeployed.rootAddress);
  return root;
}

export async function createCountryReferential(
  contracts: SmartContracts,
  owner: EthProviderInterface,
  country: string,
): Promise<SmartContractInstance> {
  const countryContract = contracts.get(contractsNames.refdiamond.country.intf);
  const countryDiamond = new Diamond(
    {
      combinedJson: contracts.combined,
      rootName: contractsNames.refdiamond.country.base,
      readableName: contractsNames.refdiamond.country.readable,
      writableName: contractsNames.refdiamond.country.writable,
      facetNames: [
        contractsNames.oppenzeppelin.ownable,
        contractsNames.refdiamond.country.bankController,
        contractsNames.refdiamond.country.countryState,
      ],
      initializeFunctionName: "initialize",
      initializeFunctionArgs: [Buffer.from(country.slice(0, 2))],
    },
    executioner(contracts, owner),
  );
  const countryDeployed = await countryDiamond.deploy();
  const countryInstance = countryContract.at(countryDeployed.rootAddress);
  return countryInstance;
}

export async function createBankModule(
  contracts: SmartContracts,
  owner: EthProviderInterface,
  ref: SmartContractInstance, // the global referential instance
  bic: string,
  id: ReturnType<typeof bankIdentifier>,
  ccy: string,
  decimals: number,
): Promise<SmartContractInstance> {
  const bankContract = contracts.get(contractsNames.cashdiamond.bank.intf);
  const bankDiamond = new Diamond(
    {
      combinedJson: contracts.combined,
      rootName: contractsNames.cashdiamond.bank.base,
      readableName: contractsNames.cashdiamond.bank.readable,
      writableName: contractsNames.cashdiamond.bank.writable,
      facetNames: [
        contractsNames.oppenzeppelin.ownable,
        // contractsNames.cashdiamond.bank.identity,
        // contractsNames.cashdiamond.bank.iban,
        contractsNames.cashdiamond.bank.extService, // already has identity and iban
        contractsNames.cashdiamond.bank.whitelist,
        contractsNames.cashdiamond.bank.boService,
        contractsNames.cashdiamond.bank.boPayment,
        contractsNames.cashdiamond.bank.extPayment,
        contractsNames.cashdiamond.bank.simulation,
      ],
      initializeFunctionName: "initialize",
      initializeFunctionArgs: [
        ref.deployedAt,
        Buffer.from(bic),
        id,
        Buffer.from(ccy),
        decimals,
      ],
    },
    executioner(contracts, owner),
  );
  const bankDeployed = await bankDiamond.deploy();
  const bankInstance = bankContract.at(bankDeployed.rootAddress);
  return bankInstance;
}

export async function createAccount(
  name: string,
  inBank: SmartContractInstance,
  owner: EthProviderInterface,
  forBank?: SmartContractInstance,
): Promise<SmartContractInstance> {
  const accountContract = getSoCashContracts().get(
    contractsNames.cashdiamond.account.intf,
  );
  const accountDiamond = new Diamond(
    {
      combinedJson: getSoCashCombinedJson(),
      rootName: contractsNames.cashdiamond.account.base,
      readableName: contractsNames.cashdiamond.account.readable,
      writableName: contractsNames.cashdiamond.account.writable,
      facetNames: [
        contractsNames.oppenzeppelin.ownable,
        contractsNames.cashdiamond.account.whitelist,
        contractsNames.cashdiamond.account.data,
        contractsNames.cashdiamond.account.htlc,
        contractsNames.cashdiamond.account.actions,
      ],
      initializeFunctionName: "initialize",
      initializeFunctionArgs: [name],
    },
    executioner(getSoCashContracts(), owner),
    [/diamond/, /fever-tokens/, /openzeppelin/],
  );
  const accountDeployed = await accountDiamond.deploy();
  // const account = await accountContract.deploy(owner.newi(), name);
  const account = accountContract.at(accountDeployed.rootAddress);
  map(account.deployedAt, name);
  await account.transferOwnership(owner.send(), inBank.deployedAt);
  await inBank.registerAccount(owner.send(), account.deployedAt);
  if (forBank) {
    // link the account to the bank for which this account is a nostro
    await account.setAttributeAddr(
      owner.send(),
      toBuffer("soCashBank"),
      forBank.deployedAt,
    );
    await account.whitelist(owner.send(), forBank.deployedAt);
  }
  return account;
}

export async function createFXProvider(
  contracts: SmartContracts,
  owner: EthProviderInterface,
  ref: SmartContractInstance, // the global referential instance
  bic: string,
  id: ReturnType<typeof bankIdentifier>,
  signer: string,
): Promise<SmartContractInstance> {
  const fxContract = contracts.get(contractsNames.cashdiamond.fxprovider.intf);
  const fxDiamond = new Diamond(
    {
      combinedJson: contracts.combined,
      rootName: contractsNames.cashdiamond.fxprovider.base,
      readableName: contractsNames.cashdiamond.fxprovider.readable,
      writableName: contractsNames.cashdiamond.fxprovider.writable,
      facetNames: [
        contractsNames.oppenzeppelin.ownable,
        contractsNames.cashdiamond.fxprovider.identity,
        contractsNames.cashdiamond.fxprovider.whitelist,
        contractsNames.cashdiamond.fxprovider.fxprovider,
      ],
      initializeFunctionName: "initialize",
      initializeFunctionArgs: [ref.deployedAt, Buffer.from(bic), id, signer],
    },
    executioner(contracts, owner),
  );
  const fxDeployed = await fxDiamond.deploy();
  const fxInstance = fxContract.at(fxDeployed.rootAddress);
  return fxInstance;
}

export async function createHTLCData() {
  const secret = crypto.randomBytes(32).toString("hex");
  const cancelSecret = crypto.randomBytes(32).toString("hex");
  const hash = "0x" + (sha256(secret) || "");
  const cancelHash = "0x" + (sha256(cancelSecret) || "");
  const tradeId = crypto.randomUUID();
  const blockTime = await blockTimestamp();
  const timeout = blockTime + 120; // 2 minute
  const id = ""; // to be filled later
  return { id, secret, cancelSecret, hash, cancelHash, tradeId, timeout };
}

export function receipientInfo(account?: string, bic?: string, iban?: string) {
  if (account)
    return { account, bic: Buffer.alloc(11), iban: Buffer.alloc(32) };
  if (bic || iban) {
    let buff = Buffer.alloc(32);
    Buffer.from(iban || "").copy(buff, 0);
    const r = {
      account: ZeroAddress,
      bic: bic
        ? Buffer.from(`${bic}           `.slice(0, 11))
        : Buffer.alloc(11),
      iban: buff,
    };
    // console.log("Recipient Info", { account, bic, iban }, r);

    return r;
  } else {
    return {
      account: ZeroAddress,
      bic: Buffer.alloc(11),
      iban: Buffer.alloc(32),
    };
  }
}

export function bankIdentifier(country: string, codes: string[]) {
  return {
    country: toBuffer(country, 2),
    codes: codes.map((c) => toBuffer(c, 10)),
  };
}

export function bankAccountSoCash(
  bank: SmartContractInstance,
  account: SmartContractInstance,
) {
  return {
    model: 1,
    bank: bank.deployedAt,
    account: account.deployedAt,
  };
}

export function bankAccountERC20(
  bank: SmartContractInstance,
  account?: string,
) {
  return {
    model: 2,
    bank: bank.deployedAt,
    account: account || ZeroAddress,
  };
}
