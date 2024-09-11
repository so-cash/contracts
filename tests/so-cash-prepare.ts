import Web3 from "web3";

import allContracts from "../build";
import {
  map,
  traceEventLog,
  contractsNames,
  createAccount,
  getNewWallet,
  checkContractCompilation,
} from "./shared";

export async function prepareContracts(
  web3: Web3,
  ccy: string = "EUR",
  subs: boolean = true,
) {
  // check all contracts are present
  checkContractCompilation(allContracts, contractsNames.cash);

  const bankContract = allContracts.get(contractsNames.cash.bank);
  const accountContract = allContracts.get(contractsNames.cash.account);
  const ibanCalcContract = allContracts.get(contractsNames.cash.ibanCalc);

  const bo1User = await getNewWallet(web3, "bankWallet1", true);
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

  const bank1 = await bankContract.deploy(
    bo1User.newi(),
    Buffer.from("AGRIFRPPXXX"),
    Buffer.from("30002"),
    Buffer.from("05728"),
    Buffer.from(ccy),
    2,
  );
  map(bank1.deployedAt, "Bank1" + ccy);
  const bank2 = await bankContract.deploy(
    bo2User.newi(),
    Buffer.from("SGXXFRPPXXX"),
    Buffer.from("40000"),
    Buffer.from("99999"),
    Buffer.from(ccy),
    2,
  );
  map(bank2.deployedAt, "Bank2" + ccy);

  // Add the IBAN calculator
  const ibanCalc = await ibanCalcContract.deploy(user1.newi());
  map(ibanCalc.deployedAt, "IBANCalc");
  await bank1.setIBANCalculator(bo1User.send(), ibanCalc.deployedAt);
  await bank2.setIBANCalculator(bo2User.send(), ibanCalc.deployedAt);

  const nostroBank1 = await createAccount("Bank1Nostro" + ccy, bank2, bo2User);
  const nostroBank2 = await createAccount("Bank2Nostro" + ccy, bank1, bo1User);

  // create the interbank registration
  await bank1.registerCorrespondent(
    bo1User.send(),
    bank2.deployedAt,
    nostroBank2.deployedAt,
    nostroBank1.deployedAt,
  );
  await bank2.registerCorrespondent(
    bo2User.send(),
    bank1.deployedAt,
    nostroBank1.deployedAt,
    nostroBank2.deployedAt,
  );

  return {
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

export async function prepareMultyCcyContracts(
  web3: Web3,
  ccy1: string = "EUR",
  ccy2: string = "USD",
  subs: boolean = true,
) {
  // check all contracts are present
  checkContractCompilation(allContracts, contractsNames.cash);
  const bankContract = allContracts.get(contractsNames.cash.bank);
  const accountContract = allContracts.get(contractsNames.cash.account);
  const ibanCalcContract = allContracts.get(contractsNames.cash.ibanCalc);

  const bo1User = await getNewWallet(web3, "bankWallet1", true);
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

  const bankCcy1 = await bankContract.deploy(
    bo1User.newi(),
    Buffer.from("AGRIFRPP"),
    Buffer.from("30002"),
    Buffer.from("05728"),
    Buffer.from(ccy1),
    2,
  );
  map(bankCcy1.deployedAt, "Bank" + ccy1);

  const bankCcy2 = await bankContract.deploy(
    bo1User.newi(),
    Buffer.from("AGRIFRPP"),
    Buffer.from("30002"),
    Buffer.from("05728"),
    Buffer.from(ccy2),
    2,
  );
  map(bankCcy2.deployedAt, "Bank" + ccy2);

  // Add the IBAN calculator
  const ibanCalc = await ibanCalcContract.deploy(user1.newi());
  map(ibanCalc.deployedAt, "IBANCalc");
  await bankCcy1.setIBANCalculator(bo1User.send(), ibanCalc.deployedAt);
  await bankCcy2.setIBANCalculator(bo1User.send(), ibanCalc.deployedAt);

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
