import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import { ganacheProvider, receipientInfo } from "./shared";
import { prepareContracts } from "./so-cash-prepare";
import e from "express";
import { createAccount } from "./shared";

describe("Test SoCash Inter Bank Functions", async function () {
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

  it("Can transfer between two accounts using bene's bank Loro", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank2, g.bo2User);

    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );

    // transfer from account 1 to account 2
    await g.bank1.transferFrom(
      g.bo1User.send(),
      account1.deployedAt,
      receipientInfo(account2.deployedAt),
      300_000,
      "Transfer to account 2",
    );
    // check the balances
    const [balance1, balance2, loroBal, nostroBal] = await Promise.all([
      g.bank1.balanceOf(g.bo1User.call(), account1.deployedAt),
      g.bank2.balanceOf(g.bo2User.call(), account2.deployedAt),
      g.bank1.balanceOf(g.bo1User.call(), g.nostroBank2.deployedAt),
      g.bank2.balanceOf(g.bo2User.call(), g.nostroBank1.deployedAt),
    ]);
    expect(balance1).to.equal("700000"); // 1_000_000 - 300_000
    expect(balance2).to.equal("300000");
    expect(loroBal).to.equal("300000");
    expect(nostroBal).to.equal("0");
  });

  it("Can transfer between two accounts using nostro", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank2, g.bo2User);
    // we need a balance in bank1 nostro
    await g.bank2.credit(
      g.bo2User.send(),
      g.nostroBank1.deployedAt,
      500_000,
      "Nostro funding",
    );
    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );

    // transfer from account 1 to account 2
    // the instance Bank1 should be allowed to operate its nostro
    await g.nostroBank1.whitelist(g.bo2User.send(), g.bank1.deployedAt);
    await g.bank1.transferFrom(
      g.bo1User.send(),
      account1.deployedAt,
      receipientInfo(account2.deployedAt),
      300_000,
      "Transfer to account 2",
    );
    // check the balances
    const [balance1, balance2, loroBal, nostroBal] = await Promise.all([
      g.bank1.balanceOf(g.bo1User.call(), account1.deployedAt),
      g.bank2.balanceOf(g.bo2User.call(), account2.deployedAt),
      g.bank1.balanceOf(g.bo1User.call(), g.nostroBank2.deployedAt),
      g.bank2.balanceOf(g.bo2User.call(), g.nostroBank1.deployedAt),
    ]);
    expect(balance1).to.equal("700000"); // 1_000_000 - 300_000
    expect(balance2).to.equal("300000");
    expect(loroBal).to.equal("0");
    expect(nostroBal).to.equal("200000"); // 500_000 - 300_000
  });

  it("Can transfer using an IBAN", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank2, g.bo2User);
    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );

    // Get account 2 IBAN
    const iban = await g.bank2.ibanOf(g.bo2User.call(), account2.deployedAt);

    // Make the transfer
    await g.bank1.transferFrom(
      g.bo1User.send(),
      account1.deployedAt,
      receipientInfo(undefined, undefined, iban),
      300_000,
      "Transfer to " + iban,
    );
    // check the balances
    const [balance1, balance2, loroBal, nostroBal] = await Promise.all([
      g.bank1.balanceOf(g.bo1User.call(), account1.deployedAt),
      g.bank2.balanceOf(g.bo2User.call(), account2.deployedAt),
      g.bank1.balanceOf(g.bo1User.call(), g.nostroBank2.deployedAt),
      g.bank2.balanceOf(g.bo2User.call(), g.nostroBank1.deployedAt),
    ]);
    expect(balance1).to.equal("700000"); // 1_000_000 - 300_000
    expect(balance2).to.equal("300000");
    expect(loroBal).to.equal("300000");
    expect(nostroBal).to.equal("0");
  });
});
