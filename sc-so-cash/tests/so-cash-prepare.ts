import Web3 from "web3";

import referentialContracts from "@so-cash/sc-so-cash-ref";
import allContracts from "../build";
import accContractsJson from "../build/combined.json" assert { type: "json" };
import {
  map,
  traceEventLog,
  contractsNames,
  createAccount,
  getNewWallet,
  checkContractCompilation,
  bankIdentifier,
  bankAccountSoCash,
  toBuffer,
  bankAccountERC20,
  receipientInfo,
  mapValue,
  cleanStruct,
  extractErrorMessage,
  ZeroAddress,
  setSoCashCombinedJson,
  createRootReferential,
  createCountryReferential,
} from "@so-cash/sc-shared";
import {
  EventReceiver,
  SmartContract,
  SmartContractInstance,
  SmartContracts,
} from "@saturn-chain/smart-contract";
import { ZeroAccount } from "./constants";
setSoCashCombinedJson(accContractsJson as any);
const Subscriptions: EventReceiver[] = [];

function addSubscription(s: EventReceiver) {
  Subscriptions.push(s);
  return s;
}

export function unsubscribeAll() {
  while (Subscriptions.length > 0) {
    const s = Subscriptions.pop();
    if (s) s.removeAllListeners();
  }
}

export function initContractCompilation(resetLibs: boolean = true) {
  // check all contracts are present
  checkContractCompilation(allContracts, contractsNames.cashdiamond);
  checkContractCompilation(allContracts, contractsNames.cash);
  checkContractCompilation(referentialContracts, contractsNames.refdiamond);
  checkContractCompilation(referentialContracts, contractsNames.ref);
  // force remove the deployed Lib address to force the redeployment of the library
  // This is because the library address is stored in the lib memory,
  // but since we create a new ganache chain for each test group, the address is not valid anymore
  if (resetLibs) {
    allContracts.get("IBANCalculator").deployedAt = undefined;
    allContracts.get("SharedFunctions").deployedAt = undefined;
    allContracts.get("PaymentEngine").deployedAt = undefined;
  }
}

export async function declareReferentials(
  web3: Web3,
  sub: boolean,
  ...countries: string[]
) {
  // const rootRef = referentialContracts.get(contractsNames.ref.root);
  // const countryRef = referentialContracts.get(contractsNames.ref.country);
  const rootUser = await getNewWallet(web3, "rootUser", true);

  const root = await createRootReferential(referentialContracts, rootUser);
  map(root.deployedAt, "RootRef");

  const countryRefs: { [key: string]: SmartContractInstance }[] = [];
  for (const country of countries) {
    const countryInst = await createCountryReferential(
      referentialContracts,
      rootUser,
      country,
    );
    map(countryInst.deployedAt, "Country" + country);
    if (sub)
      addSubscription(
        countryInst
          .allEvents(rootUser.sub(), {})
          .on("log", traceEventLog("Ref" + country)),
      );
    await root.setCountry(rootUser.send(), countryInst.deployedAt);
    const r: { [key: string]: SmartContractInstance } = {};
    r[country] = countryInst;
    countryRefs.push(r);
  }

  return {
    root,
    countries: countryRefs.reduce((acc, c) => ({ ...acc, ...c }), {}),
    rootUser,
  };
}

export async function declareBank(
  web3: Web3,
  ref: Awaited<ReturnType<typeof declareReferentials>>,
  bic: string,
  id: ReturnType<typeof bankIdentifier>,
  ccy: string = "EUR",
  decimals: number = 2,
  sub: boolean = true,
) {
  const boUser = await getNewWallet(web3, "BankWallet" + bic);
  const bankContract = allContracts.get(contractsNames.cash.bank);
  // deploy the new bank module (will deploy the libs the first time)
  const bank = await bankContract.deploy(
    boUser.newi(),
    ref.root.deployedAt,
    Buffer.from(bic),
    id,
    Buffer.from(ccy),
    decimals,
  );
  map(bank.deployedAt, "Bank:" + bic + "." + ccy);
  if (sub)
    addSubscription(
      bank
        .allEvents(boUser.sub(), {})
        .on("log", traceEventLog("BK." + bic + "." + ccy)),
    );
  const countryRef = ref.countries[id.country.toString()];
  if (!countryRef)
    throw new Error(
      `Referential Country ${id.country.toString()} not deployed`,
    );
  // register the bo wallet as the controller of the bank
  await countryRef.setBankController(
    ref.rootUser.send(),
    id.codes[0],
    await boUser.account(),
  );
  // declare the bank module in the referential
  await countryRef.setBankModule(
    boUser.send(),
    id.codes,
    Buffer.from(ccy),
    bank.deployedAt,
  );
  // const r: {
  //   [key: string]: {
  //     bank: SmartContractInstance;
  //     boUser: EthProviderInterface;
  //     id: ReturnType<typeof bankIdentifier>;
  //   };
  // } = {};
  return { bank, boUser, id, ccy };
  // return r;
}

export async function createAndRegisterNostro(
  ref: Awaited<ReturnType<typeof declareReferentials>>,
  forBank: Awaited<ReturnType<typeof declareBank>>,
  inBank: Awaited<ReturnType<typeof declareBank>>,
  name: string,
  isSSI: boolean = false,
  sub: boolean = true,
) {
  const account = await createAccount(
    name,
    inBank.bank,
    inBank.boUser,
    forBank.bank,
  );
  if (sub)
    addSubscription(
      account
        .allEvents(inBank.boUser.sub(), {})
        .on("log", traceEventLog("AC." + name)),
    );
  await forBank.bank.registerNostroAccount(
    forBank.boUser.send(),
    bankAccountSoCash(inBank.bank, account),
  );
  if (isSSI) {
    const countryRef = ref.countries[forBank.id.country.toString()];
    await countryRef.setSSI(
      forBank.boUser.send(),
      forBank.id.codes,
      toBuffer(forBank.ccy, 3),
      bankAccountSoCash(inBank.bank, account),
    );
  }
  return account;
}

export async function registerERC20Nostro(
  ref: Awaited<ReturnType<typeof declareReferentials>>,
  forBank: Awaited<ReturnType<typeof declareBank>>,
  inERC20: Awaited<ReturnType<typeof createStablecoin>>,
  isSSI: boolean = false,
) {
  await forBank.bank.registerNostroAccount(
    forBank.boUser.send(),
    bankAccountERC20(inERC20.contract, forBank.bank.deployedAt),
  );
  if (isSSI) {
    const countryRef = ref.countries[forBank.id.country.toString()];
    await countryRef.setSSI(
      forBank.boUser.send(),
      forBank.id.codes,
      toBuffer(forBank.ccy, 3),
      bankAccountERC20(inERC20.contract, forBank.bank.deployedAt),
    );
  }
  return;
}

export async function setCorrespondent(
  ref: Awaited<ReturnType<typeof declareReferentials>>,
  bank: Awaited<ReturnType<typeof declareBank>>,
  correspondent: Awaited<ReturnType<typeof declareBank>>,
) {
  const countryRef = ref.countries[bank.id.country.toString()];
  await countryRef.addCorrespondent(
    ref.rootUser.send(),
    bank.id.codes,
    Buffer.from(bank.ccy),
    correspondent.id,
  );
}

export async function createStablecoin(
  web3: Web3,
  currency: string,
  initialQty: number,
  decimals: number,
  sub: boolean = true,
) {
  const stablecoinCtr = referentialContracts.get(contractsNames.ref.stablecoin);
  const owner = await getNewWallet(web3, "CoinOwner" + currency);
  const stablecoin = await stablecoinCtr.deploy(
    owner.newi(),
    currency + "Coin",
    currency,
    initialQty,
    decimals,
  );
  map(stablecoin.deployedAt, currency + "Coin");
  if (sub)
    addSubscription(
      stablecoin
        .allEvents(owner.sub(), {})
        .on("log", traceEventLog("SC." + currency)),
    );
  return { contract: stablecoin, owner, currency };
}

function listLibraries(
  all: SmartContracts,
  name: string,
  existing: string[] = [],
): string[] {
  const contract = all.get(name);
  if (!contract) return [];
  const libs: SmartContract[] = Object.values((contract as any).requirements);
  const res = libs.map((l) => l.name);
  for (const l of libs.filter((l) => !existing.includes(l.name))) {
    const subLibs = listLibraries(all, l.name, res);
    subLibs.forEach((sl) => {
      if (!res.includes(sl)) res.push(sl);
    });
  }
  return res;
}

export async function prepareContracts(
  web3: Web3,
  ccy: string = "EUR",
  subs: boolean = true,
) {
  // check all contracts are present
  checkContractCompilation(allContracts, contractsNames.cashdiamond);
  checkContractCompilation(allContracts, contractsNames.cash);
  checkContractCompilation(referentialContracts, contractsNames.refdiamond);
  checkContractCompilation(referentialContracts, contractsNames.ref);
  // force remove the deployed Lib address to force the redeployment of the library
  // This is because the library address is stored in the lib memory,
  // but since we create a new ganache chain for each test group, the address is not valid anymore
  allContracts.get("IBANCalculator").deployedAt = undefined;
  allContracts.get("SharedFunctions").deployedAt = undefined;
  allContracts.get("PaymentEngine").deployedAt = undefined;

  console.log(
    "List libs for Bank",
    listLibraries(allContracts, contractsNames.cash.bank),
  );

  // const rootRef = referentialContracts.get(contractsNames.ref.root);
  // const countryRef = referentialContracts.get(contractsNames.ref.country);

  const bankContract = allContracts.get(contractsNames.cash.bank);
  const accountContract = allContracts.get(
    contractsNames.cashdiamond.account.intf,
  );
  // const ibanCalcContract = allContracts.get(contractsNames.cash.ibanCalc);

  const rootUser = await getNewWallet(web3, "rootUser", true);

  const bo1User = await getNewWallet(web3, "bankWallet1");
  const bank1Address = await bo1User.account();
  const bo2User = await getNewWallet(web3, "bankWallet2");
  const bank2Address = await bo2User.account();
  const user1 = await getNewWallet(web3, "userWallet1");
  const user1Address = await user1.account();
  const user2 = await getNewWallet(web3, "userWallet2");
  const user2Address = await user2.account();

  // subscribe and display all events
  const BankSubs = subs ? bankContract.allEvents(bo1User.sub(), {}) : undefined;
  if (BankSubs) BankSubs.on("log", traceEventLog("BK"));
  const AccountSubs = subs
    ? accountContract.allEvents(bo1User.sub(), {})
    : undefined;
  if (AccountSubs) AccountSubs.on("log", traceEventLog("AC"));

  // deploy the contracts

  const root = await createRootReferential(referentialContracts, rootUser);
  map(root.deployedAt, "RootRef");
  const countryFR = await createCountryReferential(
    referentialContracts,
    rootUser,
    "FR",
  );
  map(countryFR.deployedAt, "CountryFR");
  await root.setCountry(rootUser.send(), countryFR.deployedAt);
  if (subs)
    countryFR.allEvents(rootUser.sub(), {}).on("log", traceEventLog("RefFR"));

  const bank1 = await bankContract.deploy(
    bo1User.newi(),
    root.deployedAt,
    Buffer.from("AGRIFRPPXXX"),
    bankIdentifier("FR", ["30002", "05728"]),
    Buffer.from(ccy),
    2,
  );
  map(bank1.deployedAt, "Bank1" + ccy);
  const bank2 = await bankContract.deploy(
    bo2User.newi(),
    root.deployedAt,
    Buffer.from("SGXXFRPPXXX"),
    bankIdentifier("FR", ["40000", "99999"]),
    Buffer.from(ccy),
    2,
  );
  map(bank2.deployedAt, "Bank2" + ccy);

  // Add the Referential
  // await bank1.setRouterReferential(bo1User.send(), root.deployedAt);
  // await bank2.setRouterReferential(bo2User.send(), root.deployedAt);
  // Declare the modules in the referential
  const bank1Id = await bank1.bankIdentifier(bo1User.call());
  // give the bank BO the right to control the referential
  await countryFR.setBankController(
    rootUser.send(),
    bank1Id.codes[0],
    await bo1User.account(),
  );

  await countryFR.setBankModule(
    bo1User.send(),
    bank1Id.codes,
    Buffer.from(ccy),
    bank1.deployedAt,
  );
  const bank2Id = await bank2.bankIdentifier(bo2User.call());
  // give the bank BO the right to control the referential
  await countryFR.setBankController(
    rootUser.send(),
    bank2Id.codes[0],
    await bo2User.account(),
  );

  await countryFR.setBankModule(
    bo2User.send(),
    bank2Id.codes,
    Buffer.from(ccy),
    bank2.deployedAt,
  );

  // Add the IBAN calculator
  // const ibanCalc = await ibanCalcContract.deploy(user1.newi());
  // map(ibanCalc.deployedAt, "IBANCalc");
  // await bank1.setIBANCalculator(bo1User.send(), ibanCalc.deployedAt);
  // await bank2.setIBANCalculator(bo2User.send(), ibanCalc.deployedAt);

  const nostroBank1 = await createAccount(
    "Bank1Nostro" + ccy,
    bank2,
    bo2User,
    bank1,
  );
  const nostroBank2 = await createAccount(
    "Bank2Nostro" + ccy,
    bank1,
    bo1User,
    bank2,
  );

  // create the interbank registration
  // await bank1.registerCorrespondent(
  //   bo1User.send(),
  //   bank2.deployedAt,
  //   nostroBank2.deployedAt,
  //   nostroBank1.deployedAt
  // );
  // await bank2.registerCorrespondent(
  //   bo2User.send(),
  //   bank1.deployedAt,
  //   nostroBank1.deployedAt,
  //   nostroBank2.deployedAt
  // );
  await bank1.registerNostroAccount(
    bo1User.send(),
    bankAccountSoCash(bank2, nostroBank1),
  );
  await countryFR.setSSI(
    bo1User.send(),
    bank1Id.codes,
    toBuffer(ccy, 3),
    bankAccountSoCash(bank2, nostroBank1),
  );
  await bank2.registerNostroAccount(
    bo2User.send(),
    bankAccountSoCash(bank1, nostroBank2),
  );
  await countryFR.setSSI(
    bo2User.send(),
    bank2Id.codes,
    toBuffer(ccy, 3),
    bankAccountSoCash(bank1, nostroBank2),
  );

  // register the correspondent bank in the referential
  await countryFR.addCorrespondent(
    rootUser.send(),
    bank1Id.codes,
    Buffer.from(ccy),
    bank2Id,
  );
  await countryFR.addCorrespondent(
    rootUser.send(),
    bank2Id.codes,
    Buffer.from(ccy),
    bank1Id,
  );
  const paymentEngineTest = await allContracts
    .get("PaymentEngineTest")
    .deploy(rootUser.newi());

  return {
    root,
    countryFR,
    rootUser,
    paymentEngineTest,
    bankContract,
    accountContract,
    bank1,
    bank2,
    user1,
    user2,
    bank1Address,
    bank2Address,
    user1Address,
    user2Address,
    bo1User,
    bo2User,
    BankSubs,
    AccountSubs,
    nostroBank1,
    nostroBank2,
  };
}

export async function addThirdbankContract(
  web3: Web3,
  g: Awaited<ReturnType<typeof prepareContracts>>,
) {
  const ccy: string = (await g.bank1.symbol(g.bo1User.call())).replaceAll(
    "\x00",
    "",
  );
  const bo3User = await getNewWallet(web3, "bankWallet3");
  const bank3 = await g.bankContract.deploy(
    bo3User.newi(),
    g.root.deployedAt,
    Buffer.from("ABCXFRPPXXX"),
    bankIdentifier("FR", ["50000", "88888"]),
    Buffer.from(ccy),
    2,
  );
  map(bank3.deployedAt, "Bank3" + ccy);
  // await bank3.setRouterReferential(bo3User.send(), g.root.deployedAt);
  const bank3Id = await bank3.bankIdentifier(bo3User.call());
  const bank2Id = await g.bank2.bankIdentifier(g.bo2User.call());

  await g.countryFR.setBankController(
    g.rootUser.send(),
    bank3Id.codes[0],
    await bo3User.account(),
  );
  await g.countryFR.setBankModule(
    g.rootUser.send(),
    bank3Id.codes,
    Buffer.from(ccy),
    bank3.deployedAt,
  );
  // await bank3.setIBANCalculator(bo3User.send(), g.ibanCalc.deployedAt);
  const nostroBank3 = await createAccount(
    "Bank3Nostro" + ccy,
    g.bank2,
    g.bo2User,
    bank3,
  );
  const nostroBank2In3 = await createAccount(
    "Bank2NostroIn3" + ccy,
    bank3,
    bo3User,
    g.bank2,
  );
  // await bank3.registerCorrespondent(
  //   bo3User.send(),
  //   g.bank2.deployedAt,
  //   nostroBank2In3.deployedAt,
  //   nostroBank3.deployedAt
  // );

  await bank3.registerNostroAccount(
    bo3User.send(),
    bankAccountSoCash(g.bank2, nostroBank3),
  );
  await g.countryFR.setSSI(
    bo3User.send(),
    bank3Id.codes,
    toBuffer(ccy, 3),
    bankAccountSoCash(g.bank2, nostroBank3),
  );

  // await g.bank2.registerCorrespondent(
  //   g.bo2User.send(),
  //   bank3.deployedAt,
  //   nostroBank3.deployedAt,
  //   nostroBank2In3.deployedAt
  // );
  await g.bank2.registerNostroAccount(
    g.bo2User.send(),
    bankAccountSoCash(bank3, nostroBank2In3),
  );

  // We do not want the bank 2 to route to bank 3 but only to bank 1
  // await g.countryFR.addCorrespondent(
  //   g.rootUser.send(),
  //   bank2Id.codes,
  //   Buffer.from(ccy),
  //   bank3Id
  // );
  await g.countryFR.addCorrespondent(
    g.rootUser.send(),
    bank3Id.codes,
    Buffer.from(ccy),
    bank2Id,
  );
  return { ...g, bo3User, bank3, nostroBank3, nostroBank2In3 };
}

export async function prepareMultyCcyContracts(
  web3: Web3,
  ccy1: string = "EUR",
  ccy2: string = "USD",
  subs: boolean = true,
) {
  // check all contracts are present
  checkContractCompilation(allContracts, contractsNames.cashdiamond);
  checkContractCompilation(referentialContracts, contractsNames.refdiamond);
  checkContractCompilation(allContracts, contractsNames.cash);
  checkContractCompilation(referentialContracts, contractsNames.ref);
  // force remove the deployed Lib address to force the redeployment of the library
  // This is because the library address is stored in the lib memory,
  // but since we create a new ganache chain for each test group, the address is not valid anymore
  allContracts.get("IBANCalculator").deployedAt = undefined;
  allContracts.get("SharedFunctions").deployedAt = undefined;
  allContracts.get("PaymentEngine").deployedAt = undefined;

  const rootRef = referentialContracts.get(contractsNames.ref.root);
  const countryRef = referentialContracts.get(contractsNames.ref.country);

  const bankContract = allContracts.get(contractsNames.cash.bank);
  const accountContract = allContracts.get(
    contractsNames.cashdiamond.account.intf,
  );
  // const ibanCalcContract = allContracts.get(contractsNames.cash.ibanCalc);

  const rootUser = await getNewWallet(web3, "rootUser", true);

  const bo1User = await getNewWallet(web3, "bankWallet1");
  const bank1Address = await bo1User.account();
  const user1 = await getNewWallet(web3, "userWallet1");
  const user1Address = await user1.account();
  const user2 = await getNewWallet(web3, "userWallet2");
  const user2Address = await user2.account();

  // subscribe and display all events
  const BankSubs = subs ? bankContract.allEvents(bo1User.sub(), {}) : undefined;
  if (BankSubs) BankSubs.on("log", traceEventLog("BK"));
  const AccountSubs = subs
    ? accountContract.allEvents(bo1User.sub(), {})
    : undefined;
  if (AccountSubs) AccountSubs.on("log", traceEventLog("AC"));

  // deploy the contracts

  const root = await rootRef.deploy(rootUser.newi());
  map(root.deployedAt, "RootRef");
  const countryFR = await countryRef.deploy(rootUser.newi(), Buffer.from("FR"));
  map(countryFR.deployedAt, "CountryFR");
  await root.setCountry(rootUser.send(), countryFR.deployedAt);
  if (subs)
    countryFR.allEvents(rootUser.sub(), {}).on("log", traceEventLog("RefFR"));

  const bankCcy1 = await bankContract.deploy(
    bo1User.newi(),
    root.deployedAt,
    Buffer.from("AGRIFRPP"),
    bankIdentifier("FR", ["30002", "05728"]),
    Buffer.from(ccy1),
    2,
  );
  map(bankCcy1.deployedAt, "Bank" + ccy1);

  const bankCcy2 = await bankContract.deploy(
    bo1User.newi(),
    root.deployedAt,
    Buffer.from("AGRIFRPP"),
    bankIdentifier("FR", ["30002", "05728"]),
    Buffer.from(ccy2),
    2,
  );
  map(bankCcy2.deployedAt, "Bank" + ccy2);

  // Add the Referential
  // await bankCcy1.setRouterReferential(bo1User.send(), root.deployedAt);
  // await bankCcy2.setRouterReferential(bo1User.send(), root.deployedAt);
  // Declare the modules in the referential
  const bank1Id = await bankCcy1.bankIdentifier(bo1User.call());
  await countryFR.setBankController(
    rootUser.send(),
    bank1Id.codes[0],
    await bo1User.account(),
  );
  await countryFR.setBankModule(
    rootUser.send(),
    bank1Id.codes,
    Buffer.from(ccy1),
    bankCcy1.deployedAt,
  );
  const bank2Id = await bankCcy2.bankIdentifier(bo1User.call());
  await countryFR.setBankController(
    rootUser.send(),
    bank2Id.codes[0],
    await bo1User.account(),
  );
  await countryFR.setBankModule(
    rootUser.send(),
    bank2Id.codes,
    Buffer.from(ccy2),
    bankCcy2.deployedAt,
  );

  // Add the IBAN calculator
  // const ibanCalc = await ibanCalcContract.deploy(user1.newi());
  // map(ibanCalc.deployedAt, "IBANCalc");
  // await bankCcy1.setIBANCalculator(bo1User.send(), ibanCalc.deployedAt);
  // await bankCcy2.setIBANCalculator(bo1User.send(), ibanCalc.deployedAt);

  return {
    bankContract,
    accountContract,
    bankCcy1,
    bankCcy2,
    user1,
    user2,
    bank1Address,
    user1Address,
    user2Address,
    bo1User,
    BankSubs,
    AccountSubs,
  };
}

enum BankModel {
  UNDEFINED = "0",
  SO_CASH = "1",
  ERC20 = "2",
}
interface BankAccount {
  model: BankModel;
  bank: string;
  account: string;
}
interface ExplainPlanStruct {
  transferId: string;
  debitLocalAccount: string;
  creditLocalAccount: string;
  payFromNostro: string;
  payViaBank: string;
  payViaAccount: BankAccount; // { model: '2', bank: 'EURCoin', account: 'Bank:AGRIFRPP.EUR' },
  payToAccount: BankAccount; // { model: '2', bank: 'EURCoin', account: 'Bank:BOFAUS3N.EUR' }
}

export async function simulateEndToEndTransfer(
  fromBank: Awaited<ReturnType<typeof declareBank>>,
  fromAccountOrBank: SmartContractInstance, //  can be either a bank or an account if it is an interbank transfer simulation or a transfer simulation
  to: ReturnType<typeof receipientInfo>,
  amount: number,
  isInterbank = false,
): Promise<{
  error?: string;
  recipient: ReturnType<typeof receipientInfo>;
  amount: number;
  plans: { bank: string; plan: ExplainPlanStruct }[];
}> {
  const res = {
    error: undefined as string | undefined,
    recipient: to,
    amount,
    plans: [] as { bank: string; plan: ExplainPlanStruct }[],
  };

  try {
    let plan: ExplainPlanStruct = isInterbank
      ? await fromBank.bank.simulateInterbankTransfer(
          fromBank.boUser.call(),
          fromAccountOrBank.deployedAt,
          to,
          amount,
        )
      : await fromBank.bank.simulateTransfer(
          fromBank.boUser.call(),
          fromAccountOrBank.deployedAt,
          to,
          amount,
        );
    plan = cleanStruct(plan) as any;
    // fix the debit account that is not yet deployed with this fix
    if (isInterbank && plan.debitLocalAccount != ZeroAccount)
      plan.debitLocalAccount = ZeroAccount;
    // const cleaned = cleanStructAndMap(plan);
    // console.log("plan received:", cleaned);
    res.plans.push({ bank: fromBank.bank.deployedAt, plan });

    if (plan.payFromNostro != ZeroAccount) {
      // we have to simulate the payment from this account to the recipient
      const nostroInstance = allContracts
        .get(contractsNames.cashdiamond.account.intf)
        .at(plan.payFromNostro);
      const nostroBankAddress = await nostroInstance.bank(
        fromBank.boUser.call(),
      );
      const nostroBank: Awaited<ReturnType<typeof declareBank>> = {
        ...fromBank, // id is not correct but it is not used, so nevermind
        bank: allContracts.get(contractsNames.cash.bank).at(nostroBankAddress),
      };
      const subRes = await simulateEndToEndTransfer(
        nostroBank,
        nostroInstance,
        to,
        amount,
      );
      if (subRes.error) res.error = subRes.error;
      else res.plans.push(...subRes.plans);
    }
    if (plan.payViaAccount.model != BankModel.UNDEFINED) {
      // we have a transfer between this account and the payToAccount to simulate
      if (plan.payViaAccount.model == BankModel.SO_CASH) {
        const viaAccount = allContracts
          .get(contractsNames.cashdiamond.account.intf)
          .at(plan.payViaAccount.account);
        const viaAccountBank: Awaited<ReturnType<typeof declareBank>> = {
          ...fromBank,
          bank: allContracts
            .get(contractsNames.cash.bank)
            .at(plan.payViaAccount.bank),
        };
        const subRes = await simulateEndToEndTransfer(
          viaAccountBank,
          viaAccount,
          receipientInfo(plan.payToAccount.account),
          amount,
        );
        if (subRes.error) res.error = subRes.error;
        else res.plans.push(...subRes.plans);
      } else {
        // this is ERC20 model, we have nothing to simulate
        res.plans.push({
          bank: plan.payViaAccount.bank,
          plan: {
            transferId: "ERC20",
            debitLocalAccount: plan.payViaAccount.account,
            creditLocalAccount: plan.payToAccount.account,
            payFromNostro: ZeroAccount,
            payViaBank: ZeroAddress,
            payViaAccount: {
              model: BankModel.UNDEFINED,
              account: ZeroAccount,
              bank: ZeroAddress,
            },
            payToAccount: {
              model: BankModel.UNDEFINED,
              account: ZeroAccount,
              bank: ZeroAddress,
            },
          },
        });
      }
    }
    if (plan.payViaBank != ZeroAddress) {
      // we have to notify the bank of an interbank transfer
      try {
        const bankInstance = allContracts
          .get(contractsNames.cash.bank)
          .at(plan.payViaBank);
        const viaBank: Awaited<ReturnType<typeof declareBank>> = {
          ...fromBank,
          bank: bankInstance,
        };
        const subRes = await simulateEndToEndTransfer(
          viaBank,
          fromBank.bank,
          to,
          amount,
          true,
        );
        if (subRes.error) res.error = subRes.error;
        else res.plans.push(...subRes.plans);
      } catch (error: any) {
        res.error = `Impossible to accept incoming transfer: the bank ${mapValue(plan.payViaBank)} rejected with error "${extractErrorMessage(error)}"`;
        console.log(res.error);
      }
    }
  } catch (error: any) {
    res.error = `Impossible to transfer: the bank ${mapValue(fromBank.bank.deployedAt)} rejected with error "${extractErrorMessage(error)}"`;
    console.log(res.error);
  }

  // console.log("FINAL PLANS:", cleanStructAndMap(res.recipient), ...res.plans.map(p=>cleanStructAndMap(p)));

  return res;
}
