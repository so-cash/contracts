import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  cleanStruct,
  ganacheProvider,
  setMochaTimeout,
} from "@so-cash/sc-shared/utils";
import { prepareContracts } from "./so-cash-prepare";

describe("Test SoCash Bank External Functions", async function () {
  setMochaTimeout(this, 10_000);
  const web3 = new Web3(ganacheProvider() as any);
  let g: Awaited<ReturnType<typeof prepareContracts>> = {} as any;

  this.beforeEach(async () => {
    g = await prepareContracts(web3);
  });
  this.afterEach(() => {
    if (g.BankSubs) g.BankSubs.removeAllListeners();
    if (g.AccountSubs) g.AccountSubs.removeAllListeners();
  });

  it("Has the IERC20 fields", async () => {
    const [name, symbol, decimal, totalSupply] = await Promise.all([
      g.bank1.name(g.bo1User.call()),
      g.bank1.symbol(g.bo1User.call()),
      g.bank1.decimals(g.bo1User.call()),
      g.bank1.totalSupply(g.bo1User.call()),
    ]);
    // Attention name and symbol are padded with 0x00 to their fixed size
    console.log(
      name.replaceAll("\x00", ""),
      symbol.replaceAll("\x00", ""),
      decimal,
      totalSupply,
    );
  });

  it("Has the extended attributes and functions", async () => {
    const ibanOfNostro1 = await g.nostroBank1.iban(g.bo1User.call());
    console.log("IBAN of Nostro1:", ibanOfNostro1);
    const expectedIBAN = "FR794000099999EUR0000000182";
    const decoded3 = await g.paymentEngineTest.decodeIBAN(
      g.bo1User.call(),
      expectedIBAN,
    );

    const [bic, accountNumber, iban, decodedVia1, decodedVia2, codes] =
      await Promise.all([
        g.bank1.bic(g.bo1User.call()),
        g.bank1.accountNumberOf(g.bo1User.call(), g.nostroBank2.deployedAt),
        g.bank2.ibanOf(g.bo1User.call(), g.nostroBank1.deployedAt),
        g.bank1.decodeIBAN(g.bo1User.call(), ibanOfNostro1),
        g.bank2.decodeIBAN(g.bo1User.call(), ibanOfNostro1),
        g.bank1.codes(g.bo1User.call()),
      ]);
    // Attention bic and iban are padded with 0x00 to their fixed size
    console.log(
      bic.replaceAll("\x00", ""),
      "\naccount N°",
      accountNumber,
      "\nIBAN:",
      iban.replaceAll("\x00", ""),
      "\nIBAN decoded via Bank1:",
      decodedVia1,
      "\nIBAN decoded via Bank2:",
      decodedVia2,
      "\nBank code & BranchCode:",
      codes,
      "\nIBAN decoded via PaymentEngine:",
      cleanStruct(decoded3),
    );
    expect(expectedIBAN).to.equal(iban.replaceAll("\x00", ""));
    expect(decodedVia1.bank).to.equal(g.bank2.deployedAt);
    expect(decodedVia1.account).to.equal(g.nostroBank1.deployedAt);
    expect(decodedVia2.bank).to.equal(g.bank2.deployedAt);
    expect(decodedVia2.account).to.equal(g.nostroBank1.deployedAt);
  });

  it("Cannot call directly the operations dedicated to accounts", async () => {
    let p = g.bank1.transfer(
      g.bo1User.send(),
      {
        account: g.nostroBank2.deployedAt,
        bic: Buffer.from("SGXXFRPPXXX"),
        iban: Buffer.from("FR1420041010050500013M02606     "),
      },
      1000,
      "tx details",
    );
    await expect(p).to.be.rejectedWith(
      "Only a registered account can call this function",
    );
    p = g.bank1.lockFunds(g.bo1User.send(), 100);
    await expect(p).to.be.rejectedWith(
      "Only a registered account can call this function",
    );
    p = g.bank1.unlockFunds(g.bo1User.send(), 100);
    await expect(p).to.be.rejectedWith(
      "Only a registered account can call this function",
    );
  });

  it("Has the correct lock and unlocked balances", async () => {
    // First credit the account
    await g.bank1.credit(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      1_000_000,
      "Initial credit",
    );

    // Lock some funds
    await g.bank1.lockFunds(
      g.bo1User.send(),
      g.nostroBank2.deployedAt,
      100_000,
    );

    // Check the balances
    const [bal, locked, unlocked] = await Promise.all([
      g.bank1.balanceOf(g.bo1User.call(), g.nostroBank2.deployedAt),
      g.bank1.lockedBalanceOf(g.bo1User.call(), g.nostroBank2.deployedAt),
      g.bank1.unlockedBalanceOf(g.bo1User.call(), g.nostroBank2.deployedAt),
    ]);

    expect(bal).to.equal(`${1_000_000}`);
    expect(locked).to.equal(`${100_000}`);
    expect(unlocked).to.equal(`${900_000}`);
  });
});
