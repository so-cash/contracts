import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  cleanEvent,
  cleanStruct,
  ganacheProvider,
  getLogs,
  map,
  receipientInfo,
  traceEventLog,
} from "./shared";
import { prepareContracts } from "./so-cash-prepare";
import { createAccount } from "./shared";

describe("Test SoCash Bank BO Pending Functions", async function () {
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

  it("Place a debit on inactive account in pending", async () => {
    // create a client account
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    // credit the account
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      100_000,
      "Initial funding",
    );
    // deactivate the account
    await g.bank1.toggleAccountActive(g.bo1User.send(), account1.deployedAt);
    // check it is inactive
    const active = await g.bank1.isAccountActive(
      g.bo1User.call(),
      account1.deployedAt,
    );
    expect(active).to.be.false;

    // try to debit the account
    await g.bank1.debit(
      g.bo1User.send(),
      account1.deployedAt,
      10_000,
      "try a debit",
    );
    // Verify that the balance is not debited
    let balance = Number.parseInt(await account1.balance(g.bo1User.call()));
    expect(balance).to.equal(100_000);

    // get the pending info log
    let logs = await getLogs(
      g.bank1.events.TransfertStateChanged(g.bo1User.get(), {}),
    );
    // take the last one that is pending
    logs = logs.filter((l) => l.returnValues.status === "2");
    expect(logs.length).to.be.greaterThanOrEqual(1);
    const ev = cleanEvent(logs[logs.length - 1]);
    const tradeInfo = cleanStruct(
      await g.bank1.transferInfo(g.bo1User.call(), ev.returnValues.id),
    );
    console.log("transfer info", tradeInfo);
    expect(tradeInfo.status).to.equal("2");
    expect(tradeInfo.reason).to.match(/Inactive sender account/i);

    // Accept the debit
    await g.bank1.decidePendingTransfer(
      g.bo1User.send(),
      ev.returnValues.id,
      "4",
      "Accept the debit",
    );
    // Verify that the balance is debited
    balance = Number.parseInt(await account1.balance(g.bo1User.call()));
    expect(balance).to.equal(90_000);
  });
  it("Place a credit on inactive account in pending", async () => {
    // create a client account
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    // deactivate the account
    await g.bank1.toggleAccountActive(g.bo1User.send(), account1.deployedAt);
    // check it is inactive
    const active = await g.bank1.isAccountActive(
      g.bo1User.call(),
      account1.deployedAt,
    );
    expect(active).to.be.false;
    // credit the account
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      100_000,
      "Initial funding",
    );

    // Verify that the balance is not credited
    let balance = Number.parseInt(await account1.balance(g.bo1User.call()));
    expect(balance).to.equal(0);

    // get the pending info log
    let logs = await getLogs(
      g.bank1.events.TransfertStateChanged(g.bo1User.get(), {}),
    );
    // take the last one that is pending
    logs = logs.filter((l) => l.returnValues.status === "2");
    expect(logs.length).to.be.greaterThanOrEqual(1);
    const ev = cleanEvent(logs[logs.length - 1]);
    let tradeInfo = cleanStruct(
      await g.bank1.transferInfo(g.bo1User.call(), ev.returnValues.id),
    );
    console.log("transfer info", tradeInfo);
    expect(tradeInfo.status).to.equal("2");
    expect(tradeInfo.reason).to.match(/Inactive recipient account/i);

    // Accept the debit
    await g.bank1.decidePendingTransfer(
      g.bo1User.send(),
      ev.returnValues.id,
      "4",
      "Accept the credit",
    );
    // Verify that the balance is debited
    balance = Number.parseInt(await account1.balance(g.bo1User.call()));
    expect(balance).to.equal(100_000);
    tradeInfo = cleanStruct(
      await g.bank1.transferInfo(g.bo1User.call(), ev.returnValues.id),
    );
    console.log("transfer info after", tradeInfo);
    expect(tradeInfo.status).to.equal("4");
  });

  it("Place a transfer between 2 internal accounts in pending", async () => {
    // create 2 accounts
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank1, g.bo1User);
    // credit the account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      100_000,
      "Initial funding",
    );
    // deactivate the account 2
    await g.bank1.toggleAccountActive(g.bo1User.send(), account2.deployedAt);
    // check it is inactive
    let active = await g.bank1.isAccountActive(
      g.bo1User.call(),
      account2.deployedAt,
    );
    expect(active).to.be.false;

    // try to transfer between the 2 accounts
    await g.bank1.transferFrom(
      g.bo1User.send(),
      account1.deployedAt,
      receipientInfo(account2.deployedAt),
      10_000,
      "try a transfer",
    );
    // get the id of the transfer
    let logs = await getLogs(
      g.bank1.events.TransfertStateChanged(g.bo1User.get(), {}),
    );
    expect(logs.length).to.be.greaterThanOrEqual(1);
    const ev = cleanEvent(logs[logs.length - 1]); // take the last one
    let tradeInfo = cleanStruct(
      await g.bank1.transferInfo(g.bo1User.call(), ev.returnValues.id),
    );
    console.log("transfer info", tradeInfo);
    expect(tradeInfo.status).to.equal("2");
    expect(tradeInfo.reason).to.match(/Inactive recipient account/i);

    // Cancel the transfer
    await g.bank1.decidePendingTransfer(
      g.bo1User.send(),
      ev.returnValues.id,
      "3",
      "Reject the transfer",
    );
    // Verify that the balance is not debited
    let balance = Number.parseInt(await account1.balance(g.bo1User.call()));
    expect(balance).to.equal(100_000);
    balance = Number.parseInt(await account2.balance(g.bo1User.call()));
    expect(balance).to.equal(0);
    tradeInfo = cleanStruct(
      await g.bank1.transferInfo(g.bo1User.call(), ev.returnValues.id),
    );
    console.log("transfer info after", tradeInfo);
    expect(tradeInfo.status).to.equal("3");
  });

  it("Place a transfer with an external account in pending", async () => {
    // create 2 accounts
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank2, g.bo2User);
    // credit the account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      100_000,
      "Initial funding",
    );
    // deactivate the account 2
    await g.bank2.toggleAccountActive(g.bo2User.send(), account2.deployedAt);
    // check it is inactive
    let active = await g.bank2.isAccountActive(
      g.bo2User.call(),
      account2.deployedAt,
    );
    expect(active).to.be.false;

    // try to transfer between the 2 accounts
    await g.bank1.transferFrom(
      g.bo1User.send(),
      account1.deployedAt,
      receipientInfo(account2.deployedAt),
      10_000,
      "try a transfer",
    );
    // get the id of the transfer
    let logs = await getLogs(
      g.bank2.events.TransfertStateChanged(g.bo2User.get(), {}),
    );
    expect(logs.length).to.be.greaterThanOrEqual(1);
    const ev = cleanEvent(logs[logs.length - 1]); // take the last one
    let tradeInfo = cleanStruct(
      await g.bank2.transferInfo(g.bo2User.call(), ev.returnValues.id),
    );
    console.log("transfer info", tradeInfo);
    expect(tradeInfo.status).to.equal("2");
    expect(tradeInfo.reason).to.match(/Inactive recipient account/i);

    // Resume the transfer on the remote bank
    await g.bank2.decidePendingTransfer(
      g.bo2User.send(),
      ev.returnValues.id,
      "4",
      "Complete credit",
    );
    // Verify that the balances
    let balance = Number.parseInt(await account1.balance(g.bo1User.call()));
    expect(balance).to.equal(90_000);
    balance = Number.parseInt(await account2.balance(g.bo1User.call()));
    expect(balance).to.equal(10_000);
    tradeInfo = cleanStruct(
      await g.bank2.transferInfo(g.bo1User.call(), ev.returnValues.id),
    );
    console.log("transfer info after", tradeInfo);
    expect(tradeInfo.status).to.equal("4");
  });
});
