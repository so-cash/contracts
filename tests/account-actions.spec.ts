import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  cleanStruct,
  ganacheProvider,
  getLogs,
  receipientInfo,
} from "./shared";
import { prepareContracts } from "./so-cash-prepare";
import { createAccount } from "./shared";

describe("Test SoCash Accounts Functions", async function () {
  this.timeout(10000);
  const web3 = new Web3(ganacheProvider() as any);
  let g: Awaited<ReturnType<typeof prepareContracts>> = {} as any;

  this.beforeEach(async () => {
    g = await prepareContracts(web3);
  });
  this.afterEach(() => {
    if (g.BankSubs) g.BankSubs.removeAllListeners();
    if (g.AccountSubs) g.AccountSubs.removeAllListeners();
  });

  it("Get the base attributes", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);

    const [bank, iban, accountNumber, balance, lockedBalance, unlockedBalance] =
      await Promise.all([
        account1.bank(g.bo1User.call()),
        account1.iban(g.bo1User.call()),
        account1.accountNumber(g.bo1User.call()),
        account1.balance(g.bo1User.call()),
        account1.lockedBalance(g.bo1User.call()),
        account1.unlockedBalance(g.bo1User.call()),
      ]);

    console.log(
      "bank",
      bank,
      "\niban",
      iban,
      "\naccountNumber",
      accountNumber,
      "\nbalance",
      balance,
      "\nlockedBalance",
      lockedBalance,
      "\nunlockedBalance",
      unlockedBalance,
    );
  });

  it("Get and set custom attributes", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    await account1.whitelist(g.bo1User.send(), g.user1Address);

    // set a string atttribute
    await account1.setAttributeStr(
      g.user1.send(),
      web3.utils.sha3("ATT_NAME_STR"),
      "ATT_VALUE",
    );
    // set a number attribute
    await account1.setAttributeNum(
      g.user1.send(),
      web3.utils.sha3("ATT_NAME_INT"),
      123456,
    );
    // check the result
    const [attStr, attNum] = await Promise.all([
      account1.getAttributeStr(g.user1.call(), web3.utils.sha3("ATT_NAME_STR")),
      account1.getAttributeNum(g.user1.call(), web3.utils.sha3("ATT_NAME_INT")),
    ]);
    expect(attStr).to.equal("ATT_VALUE");
    expect(attNum).to.equal("123456");
  });

  it("Can transfer using the transferEx", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank1, g.bo1User);
    await account1.whitelist(g.bo1User.send(), g.user1Address);

    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );

    // User 1 to transfer to account 2
    await account1.transferEx(
      g.user1.send(),
      receipientInfo(account2.deployedAt),
      300_000,
      "Transfer to account 2",
    );
    // check the balances
    const [balance1, balance2] = await Promise.all([
      account1.balance(g.bo1User.call()),
      account2.balance(g.bo1User.call()),
    ]);
    expect(balance1).to.equal("700000"); // 1_000_000 - 300_000
    expect(balance2).to.equal("300000");

    // check the logs
    const logs = await getLogs(
      g.bank1.events.TransferEx(g.user1.get(), {
        from: account1.deployedAt,
        to: account2.deployedAt,
      }),
    );
    expect(logs.length).to.equal(1);
    expect(logs[0].returnValues.value).to.equal("300000");
    // Check the content of the transfer info
    const id = logs[0].returnValues.id;
    const transferInfo = cleanStruct(
      await g.bank1.transferInfo(g.bo1User.call(), id),
    );
    console.log("transferInfo", transferInfo);

    expect(transferInfo.sender).to.equal(account1.deployedAt);
    expect(transferInfo.recipient.account).to.equal(account2.deployedAt);
    expect(transferInfo.details).to.equal("Transfer to account 2");
  });
});
