import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import { ganacheProvider, getLogs } from "./shared";
import { prepareContracts } from "./so-cash-prepare";
import { createAccount, getNewWallet } from "./shared";

describe("Test SoCash Accounts ERC20 Compatibility", async function () {
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

  it("Has the metadata attributes", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);

    const [name, symbol, decimals, totalSupply] = await Promise.all([
      account1.name(g.bo1User.call()),
      account1.symbol(g.bo1User.call()),
      account1.decimals(g.bo1User.call()),
      account1.totalSupply(g.bo1User.call()),
    ]);
    expect(name).to.equal("Account1");
    expect(symbol).to.equal("EUR");
    expect(decimals).to.equal("2");
    expect(totalSupply).to.equal("0");
  });

  it("Can make transfers", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank1, g.bo1User);
    account1.whitelist(g.bo1User.send(), g.user1Address);

    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );

    // User 1 to transfer to account 2
    await account1.transfer(g.user1.send(), account2.deployedAt, 300_000);

    // check the balances
    const [balance1, balance2] = await Promise.all([
      account1.balanceOf(g.bo1User.call(), account1.deployedAt),
      account2.balanceOf(g.bo1User.call(), account2.deployedAt),
    ]);
    expect(balance1).to.equal("700000"); // 1_000_000 - 300_000
    expect(balance2).to.equal("300000");
    // Check the logs but not from the account but from the bank ! Not fully ERC20 compliant
    const logs = await getLogs(
      g.bank1.events.Transfer(g.user1.get(), {
        from: account1.deployedAt,
        to: account2.deployedAt,
      }),
    );
    expect(logs.length).to.equal(1);
    expect(logs[0].returnValues.value).to.equal("300000");

    // Check the totalSupply is the banlance of account1
    const [totalSupply, balance] = await Promise.all([
      account1.totalSupply(g.bo1User.call()),
      account1.balanceOf(g.bo1User.call(), account1.deployedAt),
    ]);
    expect(totalSupply).to.equal("700000");
    expect(totalSupply).to.equal(balance);
  });

  it("Can allow 3rd party to make a transfer", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank1, g.bo1User);
    account1.whitelist(g.bo1User.send(), g.user1Address);
    const thirdParty = await getNewWallet(web3, "thirdParty");

    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );
    // User1 approve the third party to transfer
    await account1.approve(g.user1.send(), await thirdParty.account(), 300_000);
    // chech the allowance
    let allowance = await account1.allowance(
      g.bo1User.call(),
      account1.deployedAt,
      await thirdParty.account(),
    );
    expect(allowance).to.equal("300000");

    // Third party to transfer to account 2
    await account1.transferFrom(
      thirdParty.send(),
      account1.deployedAt,
      account2.deployedAt,
      300_000,
    );

    // chech the allowance
    allowance = await account1.allowance(
      g.bo1User.call(),
      account1.deployedAt,
      await thirdParty.account(),
    );
    expect(allowance).to.equal("0");
    // Check the balance
    const [balance1, balance2] = await Promise.all([
      account1.balanceOf(g.bo1User.call(), account1.deployedAt),
      account2.balanceOf(g.bo1User.call(), account2.deployedAt),
    ]);
    expect(balance1).to.equal("700000"); // 1_000_000 - 300_000
    expect(balance2).to.equal("300000");

    // Check the Approval log
    const logs = await getLogs(
      account1.events.Approval(thirdParty.get(), {
        owner: account1.deployedAt,
        spender: await thirdParty.account(),
      }),
    );
    expect(logs.length).to.equal(2);
    expect(logs[0].returnValues.value).to.equal("300000");
    expect(logs[1].returnValues.value).to.equal("0");
  });

  it("Fails to transfer without the approval", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank1, g.bo1User);
    account1.whitelist(g.bo1User.send(), g.user1Address);
    const thirdParty = await getNewWallet(web3, "thirdParty");

    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );
    // chech the allowance is not set
    let allowance = await account1.allowance(
      g.bo1User.call(),
      account1.deployedAt,
      await thirdParty.account(),
    );
    expect(allowance).to.equal("0");

    // Third party tries to transfer to account 2
    const p = account1.transferFrom(
      thirdParty.send(),
      account1.deployedAt,
      account2.deployedAt,
      300_000,
    );
    await expect(p).to.be.rejectedWith("transfer amount exceeds allowance");
  });

  it("Can use a partial allowance", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account2 = await createAccount("Account2", g.bank1, g.bo1User);
    account1.whitelist(g.bo1User.send(), g.user1Address);
    const thirdParty = await getNewWallet(web3, "thirdParty");

    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );
    // User1 approve the third party to transfer
    await account1.approve(g.user1.send(), await thirdParty.account(), 300_000);
    // chech the allowance
    let allowance = await account1.allowance(
      g.bo1User.call(),
      account1.deployedAt,
      await thirdParty.account(),
    );
    expect(allowance).to.equal("300000");

    // Third party to transfer to account 2 a first part of 100 000
    await account1.transferFrom(
      thirdParty.send(),
      account1.deployedAt,
      account2.deployedAt,
      100_000,
    );

    // chech the allowance
    allowance = await account1.allowance(
      g.bo1User.call(),
      account1.deployedAt,
      await thirdParty.account(),
    );
    expect(allowance).to.equal("200000"); // 300_000 - 100_000

    // Third party to transfer to account 2 a second part of 200 000
    await account1.transferFrom(
      thirdParty.send(),
      account1.deployedAt,
      account2.deployedAt,
      200_000,
    );

    // chech the allowance
    allowance = await account1.allowance(
      g.bo1User.call(),
      account1.deployedAt,
      await thirdParty.account(),
    );
    expect(allowance).to.equal("0");
  });
});
