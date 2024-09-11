import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  cleanStruct,
  ganacheProvider,
  getLogs,
  receipientInfo,
} from "./shared/utils";
import { prepareMultyCcyContracts } from "./so-cash-prepare";
import { createAccount } from "./shared";

describe("Test SoCash Accounts with multi currencies", async function () {
  this.timeout(10000);
  const web3 = new Web3(ganacheProvider() as any);
  let g: Awaited<ReturnType<typeof prepareMultyCcyContracts>> = {} as any;

  this.beforeEach(async () => {
    g = await prepareMultyCcyContracts(web3);
  });
  this.afterEach(() => {
    if (g.BankSubs) g.BankSubs.removeAllListeners();
    if (g.AccountSubs) g.AccountSubs.removeAllListeners();
  });

  it("Should not transfer between 2 currencies", async () => {
    // Create 2 accounts in each currencies
    const account1 = await createAccount("Account1", g.bankCcy1, g.bo1User);
    const account2 = await createAccount("Account2", g.bankCcy2, g.bo1User);

    // credit the first account
    await g.bankCcy1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1000,
      "initial credit",
    );

    // Try to transfer between the 2 accounts
    const p = account1.transferEx(
      g.bo1User.send(),
      receipientInfo(account2.deployedAt),
      500,
      "test a transfer",
    );

    await expect(p).to.be.rejectedWith(
      "Expect the recipient to have the same currency and decimals as the bank",
    );
  });

  it("Should not transfer between 2 currencies using IBAN", async () => {
    // Create 2 accounts in each currencies
    const account1 = await createAccount("Account1", g.bankCcy1, g.bo1User);
    const account2 = await createAccount("Account2", g.bankCcy2, g.bo1User);

    // credit the first account
    await g.bankCcy1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1000,
      "initial credit",
    );

    const account2IBan = await account2.iban(g.bo1User.call());

    // Try to transfer between the 2 accounts
    const p = account1.transferEx(
      g.bo1User.send(),
      receipientInfo(undefined, undefined, account2IBan),
      500,
      "test a transfer",
    );

    await expect(p).to.be.rejectedWith("Currency mismatch");
  });
});
