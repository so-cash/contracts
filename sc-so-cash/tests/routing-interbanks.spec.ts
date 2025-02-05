import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  cleanEvent,
  cleanStruct,
  fromBytes,
  ganacheProvider,
  getLogs,
  setMochaTimeout,
} from "@so-cash/sc-shared/utils";
import { prepareContracts, addThirdbankContract } from "./so-cash-prepare";
import { receipientInfo, createAccount } from "@so-cash/sc-shared";

describe("Test SoCash Routing Inter Bank payments", async function () {
  setMochaTimeout(this, 15_000);
  const web3 = new Web3(ganacheProvider() as any);
  let g: Awaited<ReturnType<typeof addThirdbankContract>> = {} as any;

  this.beforeEach(async () => {
    const a = await prepareContracts(web3);
    g = await addThirdbankContract(web3, a);
  });
  this.afterEach(() => {
    if (g.BankSubs) g.BankSubs.removeAllListeners();
    if (g.AccountSubs) g.AccountSubs.removeAllListeners();
  });

  it("Has created the 3 banks structure", async () => {
    // Test that the 3 banks are correctly created with a correspondent banks setup
    // where bank1 -> bank2 -> bank3 is a valid route
    const bank1Id = await g.bank1.bankIdentifier(g.bo1User.call());
    const bank2Id = await g.bank2.bankIdentifier(g.bo2User.call());
    const bank3Id = await g.bank3.bankIdentifier(g.bo3User.call());
    interface CBRecord {
      bank: string;
      currency: string;
      correspondentCountry: string;
      correspondentBank: string;
      rawCodes: string[];
      rawCcy: string;
    }
    const events: CBRecord[] = (
      await getLogs(
        g.countryFR.events.CorrespondentBankChange(g.rootUser.get(), {}),
      )
    )
      .map(cleanEvent)
      .map((e) => e.returnValues)
      .map((d) => ({
        bank: [fromBytes(d.bankCode), ...d.codes.map(fromBytes)].join("."),
        currency: fromBytes(d.currency),
        correspondentCountry: fromBytes(d.correspondent.country),
        correspondentBank: d.correspondent.codes.map(fromBytes).join("."),
        rawCodes: [d.bankCode.slice(0, 22), ...d.codes],
        rawCcy: d.currency.slice(0, 8),
      }));

    // get the correspondent for each banks in the array of events
    const mapCorrespondents = (
      await Promise.all(
        events.map((e) =>
          g.countryFR.getCorrespondentBanks(
            g.rootUser.call(),
            e.rawCodes,
            e.rawCcy,
          ),
        ),
      )
    )
      .map(cleanStruct)
      .flat()
      .map((d, i) => ({
        country: fromBytes(d.country),
        bank: events[i].bank,
        correspondent: d.codes.map(fromBytes).join("."),
      }));
    console.log(mapCorrespondents);
    const expected = [
      { country: "FR", bank: "30002.05728", correspondent: "40000.99999" },
      { country: "FR", bank: "40000.99999", correspondent: "30002.05728" },
      { country: "FR", bank: "50000.88888", correspondent: "40000.99999" },
    ];
    expect(mapCorrespondents).to.deep.equal(expected);
  });

  it("Makes a transfer from a client in bank1 to a client in bank 3 using acc address", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account3 = await createAccount("Account3", g.bank3, g.bo3User);

    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );

    // transfer from account 1 to account 3
    await g.bank1.transferFrom(
      g.bo1User.send(),
      account1.deployedAt,
      receipientInfo(account3.deployedAt),
      300_000,
      "Transfer to account 3",
    );

    // check the balances
    const [balance1, balance3, bank2InBank1, bank3InBank2, bank2InBank3] =
      await Promise.all([
        g.bank1.balanceOf(g.bo1User.call(), account1.deployedAt),
        g.bank3.balanceOf(g.bo3User.call(), account3.deployedAt),
        g.bank1.balanceOf(g.bo1User.call(), g.nostroBank2.deployedAt),
        g.bank2.balanceOf(g.bo2User.call(), g.nostroBank3.deployedAt),
        g.bank3.balanceOf(g.bo3User.call(), g.nostroBank2In3.deployedAt),
      ]);
    expect(balance1).to.equal("700000"); // 1_000_000 - 300_000
    expect(balance3).to.equal("300000");
    expect(bank2InBank1).to.equal("300000");
    expect(bank3InBank2).to.equal("300000");
    expect(bank2InBank3).to.equal("0");
  });

  it("Makes a transfer from a client in bank1 to a client in bank 3 using acc iban", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    const account3 = await createAccount("Account3", g.bank3, g.bo3User);

    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );

    // transfer from account 1 to account 3
    const iban3 = await account3.iban(g.bo3User.call());
    console.log("IBAN3", iban3);

    await g.bank1.transferFrom(
      g.bo1User.send(),
      account1.deployedAt,
      receipientInfo(undefined, undefined, iban3),
      300_000,
      "Transfer to account 3",
    );

    // check the balances
    const [balance1, balance3, bank2InBank1, bank3InBank2, bank2InBank3] =
      await Promise.all([
        g.bank1.balanceOf(g.bo1User.call(), account1.deployedAt),
        g.bank3.balanceOf(g.bo3User.call(), account3.deployedAt),
        g.bank1.balanceOf(g.bo1User.call(), g.nostroBank2.deployedAt),
        g.bank2.balanceOf(g.bo2User.call(), g.nostroBank3.deployedAt),
        g.bank3.balanceOf(g.bo3User.call(), g.nostroBank2In3.deployedAt),
      ]);
    expect(balance1).to.equal("700000"); // 1_000_000 - 300_000
    expect(balance3).to.equal("300000");
    expect(bank2InBank1).to.equal("300000");
    expect(bank3InBank2).to.equal("300000");
    expect(bank2InBank3).to.equal("0");
  });

  it("Makes a transfer from a client in bank1 to bank3 bic and a false IBAN should fail", async () => {
    const account1 = await createAccount("Account1", g.bank1, g.bo1User);
    // we use an IBAN that would decode to bank3 but does not match any actual account
    const Bank3Iban = "FR375000088888EUR0000000079"; // valid checksum on account zero

    // credit account 1
    await g.bank1.credit(
      g.bo1User.send(),
      account1.deployedAt,
      1_000_000,
      "Initial credit",
    );

    // transfer from account 1 to account 3
    const bic3 = await g.bank3.bic(g.bo3User.call());
    const p = g.bank1.transferFrom(
      g.bo1User.send(),
      account1.deployedAt,
      receipientInfo(undefined, bic3, Bank3Iban),
      300_000,
      "Transfer to account 3",
    );

    await expect(p).to.be.rejectedWith("Target account not found in the bank");
  });
});
