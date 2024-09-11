import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import { ganacheProvider, getLogs } from "./shared";
import { prepareContracts } from "./so-cash-prepare";

describe("Test SoCash Bank BO Functions", async function () {
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

  it("Validate the correspondent banking setup", async () => {
    const cb2 = await g.bank1.correspondent(
      g.bo1User.call(),
      g.bank2.deployedAt,
    );
    const cb1 = await g.bank2.correspondent(
      g.bo2User.call(),
      g.bank1.deployedAt,
    );

    expect(cb1.loro).to.equal(g.nostroBank1.deployedAt);
    expect(cb1.nostro).to.equal(g.nostroBank2.deployedAt);
    expect(cb2.loro).to.equal(g.nostroBank2.deployedAt);
    expect(cb2.nostro).to.equal(g.nostroBank1.deployedAt);
    expect(cb1.registered).to.be.true;
    expect(cb2.registered).to.be.true;
    expect(cb1.lastNostroBalance).to.equal("0");
    expect(cb2.lastNostroBalance).to.equal("0");

    // extract the initial balances
    const balance1 = Number.parseInt(
      await g.nostroBank1.balance(g.bo1User.call()),
    );
    const balance2 = Number.parseInt(
      await g.nostroBank2.balance(g.bo2User.call()),
    );
    expect(balance1).to.equal(0);
    expect(balance2).to.equal(0);

    // check the events generated
    let logs: Awaited<ReturnType<typeof getLogs>>;
    logs = await getLogs(
      g.bank1.events.AccountRegistration(g.user1.get(), {
        account: g.nostroBank2.deployedAt,
      }),
    );
    expect(logs.length).to.equal(1);
    expect(logs[0].returnValues.registered).to.equal(true);
    logs = await getLogs(
      g.bank1.events.BankRegistration(g.user1.get(), {
        bank: g.bank2.deployedAt,
      }),
    );
    expect(logs.length).to.equal(1);
    expect(logs[0].returnValues.registered).to.equal(true);

    // check that the isAccountRegistered returns true
    const isRegistered = await g.bank1.isAccountRegistered(
      g.bo1User.call(),
      g.nostroBank2.deployedAt,
    );
    expect(isRegistered).to.be.true;
    // check that the isCorrespondentRegistered returns true
    const isCorrespondent = await g.bank1.isCorrespondentRegistered(
      g.bo1User.call(),
      g.bank2.deployedAt,
    );
    expect(isCorrespondent).to.be.true;
    // check the account is active
    const active = await g.bank1.isAccountActive(
      g.bo1User.call(),
      g.nostroBank2.deployedAt,
    );
    expect(active).to.be.true;
  });

  it("Can unregister an account", async () => {
    await g.bank1.unregisterAccount(g.bo1User.send(), g.nostroBank2.deployedAt);
    // check if the account is still registered
    const isRegistered = await g.bank1.isAccountRegistered(
      g.bo1User.call(),
      g.nostroBank2.deployedAt,
    );
    expect(isRegistered).to.be.false;
    // check the event was received
    const logs = await getLogs(
      g.bank1.events.AccountRegistration(g.user1.get(), {
        account: g.nostroBank2.deployedAt,
      }),
    );
    expect(logs.length).to.equal(2);
    expect(logs[1].returnValues.registered).to.equal(false);
  });

  it("Can unregister a bank", async () => {
    await g.bank1.unregisterCorrespondent(g.bo1User.send(), g.bank2.deployedAt);
    // check if the account is still registered
    const isRegistered = await g.bank1.isCorrespondentRegistered(
      g.bo1User.call(),
      g.bank2.deployedAt,
    );
    expect(isRegistered).to.be.false;
    // check the event was received
    const logs = await getLogs(
      g.bank1.events.BankRegistration(g.user1.get(), {
        account: g.bank2.deployedAt,
      }),
    );
    expect(logs.length).to.equal(2);
    expect(logs[1].returnValues.registered).to.equal(false);
  });

  it("Credit an account", async () => {
    await g.bank1.credit(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      1_000_000,
      "First credit",
    );
    let logs = await getLogs(
      g.bank1.events.TransferEx(g.bo1User.get(), {
        to: g.nostroBank2.deployedAt,
      }),
    );
    expect(logs.length).to.equal(1);
    const txInfo = await g.bank1.transferInfo(
      g.bo1User.call(),
      Number.parseInt(logs[0].returnValues.id),
    );
    expect(txInfo.details).to.equal("First credit");
    logs = await getLogs(
      g.bank1.events.Transfer(g.bo1User.get(), {
        to: g.nostroBank2.deployedAt,
      }),
    );
    expect(logs.length).to.equal(1);
    expect(logs[0].returnValues.value).to.equal("1000000");
    const bal = Number.parseInt(await g.nostroBank2.balance(g.bo1User.call()));
    expect(bal).to.equal(1_000_000);
    // check the local value of the nostro
    const cb1 = await g.bank2.correspondent(
      g.bo2User.call(),
      g.bank1.deployedAt,
    );
    expect(cb1.lastNostroBalance).to.equal("1000000");
  });

  it("Debit an account", async () => {
    // initialize the account with a credit
    await g.bank1.credit(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      1_000_000,
      "First credit",
    );

    // debit the account
    await g.bank1.debit(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      500_000,
      "First debit",
    );
    const bal = Number.parseInt(await g.nostroBank2.balance(g.bo1User.call()));
    expect(bal).to.equal(500_000);
    // Check the second TransferEx event exists
    let logs = await getLogs(
      g.bank1.events.TransferEx(g.bo1User.get(), {
        from: g.nostroBank2.deployedAt,
        id: 2,
      }),
    );
    expect(logs.length).to.equal(1);
    // check the local value of the nostro
    const cb1 = await g.bank2.correspondent(
      g.bo2User.call(),
      g.bank1.deployedAt,
    );
    expect(cb1.lastNostroBalance).to.equal("500000");
  });

  it("Locks the funds so cannot be debited", async () => {
    // initialize the account with a credit
    await g.bank1.credit(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      1_000_000,
      "First credit",
    );

    // lock the funds
    await g.bank1.lockFunds(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      500_000,
    );
    // debit the account with the full balance
    const bal = Number.parseInt(await g.nostroBank2.balance(g.bo1User.call()));
    const p = g.bank1.debit(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      bal,
      "Force debit",
    );
    await expect(p).to.be.rejectedWith("Insufficient funds");

    // Unlock the funds and debit the account
    await g.bank1.unlockFunds(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      500_000,
    );
    await g.bank1.debit(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      bal,
      "Force debit",
    );
    const bal2 = Number.parseInt(await g.nostroBank2.balance(g.bo1User.call()));
    expect(bal2).to.equal(0);
  });

  it("Lock more than the balance fails", async () => {
    // initialize the account with a credit
    await g.bank1.credit(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      1_000_000,
      "First credit",
    );

    // lock the funds
    const p = g.bank1.lockFunds(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      1_500_000,
    );
    await expect(p).to.be.rejectedWith("Insufficient unlocked funds");
  });

  it("Unlock more than the locked balance fails", async () => {
    // initialize the account with a credit
    await g.bank1.credit(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      1_000_000,
      "First credit",
    );

    // lock the funds
    await g.bank1.lockFunds(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      500_000,
    );

    // unlock
    const p = g.bank1.unlockFunds(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      1_000_000,
    );
    await expect(p).to.be.rejectedWith("Insufficient locked funds");
  });

  it("Exchange between Nostro/Loro", async () => {
    // Credit the nostro account at the other bank
    await g.bank1.creditNostro(
      g.bo1User.send(),
      g.nostroBank1.deployedAt,
      1_000_000,
      "First credit",
    );

    // Check the balance
    let bal1 = Number.parseInt(await g.nostroBank1.balance(g.bo1User.call()));
    let bal2 = Number.parseInt(await g.nostroBank2.balance(g.bo1User.call()));
    expect(bal1).to.equal(1_000_000);
    expect(bal2).to.equal(bal1);
    // check the local value of the nostros
    let cb1 = await g.bank2.correspondent(g.bo2User.call(), g.bank1.deployedAt);
    expect(cb1.lastNostroBalance).to.equal("1000000");
    let cb2 = await g.bank1.correspondent(g.bo1User.call(), g.bank2.deployedAt);
    expect(cb2.lastNostroBalance).to.equal("1000000");

    // check the nostro account active status
    let active2 = await g.bank1.isAccountActive(
      g.bo1User.call(),
      g.nostroBank2.deployedAt,
    );
    let active1 = await g.bank2.isAccountActive(
      g.bo2User.call(),
      g.nostroBank1.deployedAt,
    );
    console.log("Active", "1:", active1, "2:", active2);

    expect(active1).to.be.true;
    expect(active2).to.be.true;

    // Request the netting of the balances
    await g.bank1.requestNetting(g.bo1User.send(), g.bank2.deployedAt, bal1);
    // Check the balance
    bal1 = Number.parseInt(await g.nostroBank1.balance(g.bo1User.call()));
    bal2 = Number.parseInt(await g.nostroBank2.balance(g.bo1User.call()));
    expect(bal1).to.equal(0);
    expect(bal2).to.equal(0);

    // check the local value of the nostros
    cb1 = await g.bank2.correspondent(g.bo2User.call(), g.bank1.deployedAt);
    expect(cb1.lastNostroBalance).to.equal("0");
    cb2 = await g.bank1.correspondent(g.bo1User.call(), g.bank2.deployedAt);
    expect(cb2.lastNostroBalance).to.equal("0");
  });
});
