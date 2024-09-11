import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import { ganacheProvider, getLogs } from "./shared/utils";
import { prepareContracts } from "./so-cash-prepare";
import { createAccount } from "./shared";

const OVERDRAFT_AMOUNT = Buffer.from("overdraftAmount");

describe("Test SoCash Overdraft capacity", async function () {
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

  it("Set the overdraft limit", async () => {
    // create a new account
    const account1 = await createAccount("Account 1", g.bank1, g.bo1User);

    // set the attribute
    await account1.setAttributeNum(
      g.bo1User.send(),
      OVERDRAFT_AMOUNT,
      10_000_00,
    );

    // Check the attribute value
    const limit = await account1.getAttributeNum(
      g.bo1User.call(),
      OVERDRAFT_AMOUNT,
    );
    expect(Number.parseInt(limit)).to.equal(10_000_00);
  });

  it("Can pay using the overdraft limit", async () => {
    // create a new account
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);

    // set the attribute
    await account1.setAttributeNum(
      g.bo1User.send(),
      OVERDRAFT_AMOUNT,
      10_000_00,
    );

    // pay using the overdraft
    await account1.transfer(
      g.bo1User.send(),
      g.nostroBank1.deployedAt,
      5_000_00,
    );

    // Check the balance
    const [fullbalance, balance] = await Promise.all([
      account1.fullBalance(g.bo1User.call()),
      account1.balance(g.bo1User.call()),
    ]);
    expect(Number.parseInt(fullbalance)).to.equal(-5_000_00);
    expect(Number.parseInt(balance)).to.equal(0);
  });

  it("Cannot pay more than the overdraft limit", async () => {
    // create a new account
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);

    // set the attribute
    await account1.setAttributeNum(
      g.bo1User.send(),
      OVERDRAFT_AMOUNT,
      10_000_00,
    );

    // pay using the overdraft
    await expect(
      account1.transfer(g.bo1User.send(), g.nostroBank1.deployedAt, 15_000_00),
    ).to.be.rejectedWith(
      "Overdraft limit would be reached, cannot debit account",
    );
  });

  it("Reception of cash on an overdraft account should reduce the overdraft", async () => {
    // create a new account
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);

    // set the attribute
    await account1.setAttributeNum(
      g.bo1User.send(),
      OVERDRAFT_AMOUNT,
      10_000_00,
    );

    // pay using the overdraft
    await account1.transfer(
      g.bo1User.send(),
      g.nostroBank1.deployedAt,
      5_000_00,
    );

    // receive cash
    await g.bank1.credit(g.bo1User.send(), account1.deployedAt, 10_000_00, "");

    // Check the balance
    const [fullbalance2, balance2] = await Promise.all([
      account1.fullBalance(g.bo1User.call()),
      account1.balance(g.bo1User.call()),
    ]);
    expect(Number.parseInt(fullbalance2)).to.equal(5_000_00);
    expect(Number.parseInt(balance2)).to.equal(5_000_00);
  });

  it("Can lock balance on the account generating a fictive overdraft", async () => {
    // create a new account
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);

    // set the attribute
    await account1.setAttributeNum(
      g.bo1User.send(),
      OVERDRAFT_AMOUNT,
      10_000_00,
    );

    // lock balance should use the overdraft
    await g.bank1.lockFunds(g.bo1User.send(), account1.deployedAt, 5_000_00);

    // Check the balance
    const [fullbalance, balance, locked, unlocked] = await Promise.all([
      account1.fullBalance(g.bo1User.call()),
      account1.balance(g.bo1User.call()),
      account1.lockedBalance(g.bo1User.call()),
      account1.unlockedBalance(g.bo1User.call()),
    ]);
    expect(Number.parseInt(fullbalance)).to.equal(0);
    expect(Number.parseInt(balance)).to.equal(0);
    expect(Number.parseInt(locked)).to.equal(5_000_00);
    expect(Number.parseInt(unlocked)).to.equal(0);
  });

  it("Cannot lock more than the overdraft limit", async () => {
    // create a new account
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);

    // set the attribute
    await account1.setAttributeNum(
      g.bo1User.send(),
      OVERDRAFT_AMOUNT,
      10_000_00,
    );

    // lock balance should use the overdraft
    await expect(
      g.bank1.lockFunds(g.bo1User.send(), account1.deployedAt, 15_000_00),
    ).to.be.rejectedWith(
      "Overdraft limit would be reached, cannot lock the amount",
    );
  });

  it("Can unlock balance that went overdraft", async () => {
    // create a new account
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);

    // set the attribute
    await account1.setAttributeNum(
      g.bo1User.send(),
      OVERDRAFT_AMOUNT,
      10_000_00,
    );

    // lock balance should use the overdraft
    await g.bank1.lockFunds(g.bo1User.send(), account1.deployedAt, 5_000_00);

    // transfer more cash
    await account1.transfer(
      g.bo1User.send(),
      g.nostroBank1.deployedAt,
      5_000_00,
    );

    // unlock balance
    await g.bank1.unlockFunds(g.bo1User.send(), account1.deployedAt, 5_000_00);

    // Check the balance
    const [fullbalance, balance, locked, unlocked] = await Promise.all([
      account1.fullBalance(g.bo1User.call()),
      account1.balance(g.bo1User.call()),
      account1.lockedBalance(g.bo1User.call()),
      account1.unlockedBalance(g.bo1User.call()),
    ]);
    console.log(
      "Full Balance",
      fullbalance,
      "Balance",
      balance,
      "Locked",
      locked,
      "Unlocked",
      unlocked,
    );

    expect(Number.parseInt(fullbalance)).to.equal(-5_000_00);
    expect(Number.parseInt(balance)).to.equal(0);
    expect(Number.parseInt(locked)).to.equal(0);
    expect(Number.parseInt(unlocked)).to.equal(0);
  });
});
