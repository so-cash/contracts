import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  ZeroAddress,
  cleanStruct,
  ganacheProvider,
  getLogs,
  toBuffer,
} from "@so-cash/sc-shared/utils";
import { prepareContracts } from "./ref-prepare";
import { EthProviderInterface } from "@saturn-chain/dlt-tx-data-functions";
import { bankAccountSoCash } from "@so-cash/sc-shared";

describe("Test so|cash basic referentials", function () {
  this.timeout(10000);

  const web3 = new Web3(ganacheProvider() as any);
  let g: Awaited<ReturnType<typeof prepareContracts>> = {} as any;

  this.beforeEach(async () => {
    g = await prepareContracts(web3);
  });
  this.afterEach(() => {
    if (g.RootSub) g.RootSub.removeAllListeners();
    if (g.CountrySub) g.CountrySub.removeAllListeners();
  });

  it("has the proper deployment", async () => {
    const FRContract = await g.root.getCountry(
      g.adminFRUser.call(),
      Buffer.from("FR"),
    );
    const USContract = await g.root.getCountry(
      g.adminUSUser.call(),
      Buffer.from("US"),
    );
    expect(FRContract).to.equal(g.countryFR.deployedAt);
    expect(USContract).to.equal(g.countryUS.deployedAt);
    console.log("FR", FRContract);
    console.log("US", USContract);

    const OtherContract = await g.root.getCountry(
      g.adminUser.call(),
      Buffer.from("XX"),
    );
    expect(OtherContract).to.equal(ZeroAddress);
  });

  it("records the SoCashBank", async () => {
    const countryCode = toBuffer("FR");
    const bankCode = toBuffer("12345", 10);
    const branchCode = toBuffer("67890", 10);
    const currency = toBuffer("EUR");
    const fakeAddress = "0x96f99909f4FE675F616E1C366B91eDBB8bcA5c98";

    const countryAddress = await g.root.getCountry(
      g.adminFRUser.call(),
      countryCode,
    );
    const country = g.countryContract.at(countryAddress);

    // allow the bank bo to set the bank module
    await country.setBankController(
      g.adminFRUser.send(),
      bankCode,
      await g.bankBOUser.account(),
    );

    await country.setBankModule(
      g.bankBOUser.send(),
      [bankCode, branchCode],
      currency,
      fakeAddress,
    );

    const foundBank = await country.getBankModule(
      g.adminFRUser.call(),
      [bankCode, branchCode],
      currency,
    );
    expect(foundBank).to.equal(fakeAddress);
  });

  it("records the correspondent bank", async () => {
    const countryCode = Buffer.from("FR");
    const bankModule = {
      bankCode: toBuffer("12345"),
      branchCode: toBuffer("67890"),
      currency: toBuffer("EUR"),
    };
    const correspondent = {
      bankCode: toBuffer("22222", 10),
      branchCode: toBuffer("90001", 10),
    };

    // register the bank module
    const countryAddress = await g.root.getCountry(
      g.adminFRUser.call(),
      countryCode,
    );
    const country = g.countryContract.at(countryAddress);
    await country.addCorrespondent(
      g.adminFRUser.send(),
      [bankModule.bankCode, bankModule.branchCode],
      bankModule.currency,
      {
        country: countryCode,
        codes: [correspondent.bankCode, correspondent.branchCode],
      },
    );
  });

  it("Record SSI for a bank", async () => {
    const countryCode = toBuffer("FR");
    const bankCode = toBuffer("12345", 10);
    const branchCode = toBuffer("67890", 10);
    const currency = toBuffer("EUR");
    const fakeBankAddress = "0x96f99909f4FE675F616E1C366B91eDBB8bcA5c98";
    const fakeAccountAddress = "0xd0701Dfd3accA791ac49a391921FF776fa9b8bC8";

    const countryAddress = await g.root.getCountry(
      g.adminFRUser.call(),
      countryCode,
    );
    const country = g.countryContract.at(countryAddress);

    // allow the bank bo to set the bank module
    await country.setBankController(
      g.adminFRUser.send(),
      bankCode,
      await g.bankBOUser.account(),
    );

    await country.setSSI(
      g.bankBOUser.send(),
      [bankCode, branchCode],
      currency,
      { model: 1, bank: fakeBankAddress, account: fakeAccountAddress },
    );

    const foundSSI = await country.getSSI(
      g.adminFRUser.call(),
      [bankCode, branchCode],
      currency,
    );

    console.log("SSI", cleanStruct(foundSSI));
    expect(foundSSI.model).to.equal("1");
    expect(foundSSI.bank).to.equal(fakeBankAddress);
    expect(foundSSI.account).to.equal(fakeAccountAddress);
  });

  it("resolve the route to the correspondent bank", async () => {
    const countryUsers: Record<string, EthProviderInterface> = {
      FR: g.adminFRUser,
      US: g.adminUSUser,
    };
    const banks: Record<string, { country: string; codes: string[] }> = {
      bank1: { country: "FR", codes: ["12345", "67890"] },
      bank2: { country: "US", codes: ["5432100"] },
      bank3: { country: "FR", codes: ["54321", "098", "XYZ"] },
    };
    const mapping = [
      { bank: "bank1", correspondent: "bank2", ccy: "USD" },
      { bank: "bank1", correspondent: "bank3", ccy: "EUR" },
      { bank: "bank2", correspondent: "bank1", ccy: "EUR" },
      { bank: "bank2", correspondent: "bank3", ccy: "EUR" },
      { bank: "bank2", correspondent: "bank3", ccy: "USD" },
      { bank: "bank3", correspondent: "bank1", ccy: "USD" },
      { bank: "bank3", correspondent: "bank2", ccy: "EUR" },
    ];

    function reformatRoute(route: {
      resolved: boolean;
      route: { country: string; codes: string[] }[];
    }): { resolved: boolean; route: string[] } {
      const bankId = (def: { country: string; codes: string[] }) =>
        `${def.country}.${def.codes.join(".")}`;
      const hexToAscii = (hex: string) =>
        Buffer.from(hex.slice(2), "hex").toString().replaceAll("\0", "");
      const reformatBank = (b: { country: string; codes: string[] }) => ({
        country: hexToAscii(b.country),
        codes: b.codes.map(hexToAscii),
      });
      const map = new Map<string, string>();
      for (const b of Object.keys(banks)) {
        map.set(bankId(banks[b]), b);
      }

      return {
        resolved: route.resolved,
        route: route.route.map((r) => map.get(bankId(reformatBank(r)))!),
      };
    }

    for (const bank of Object.keys(banks)) {
      const b = banks[bank];
      const user = countryUsers[b.country];
      const countryAddress = await g.root.getCountry(
        user.call(),
        toBuffer(b.country),
      );
      const country = g.countryContract.at(countryAddress);
      await country.setBankModule(
        user.send(),
        b.codes.map((c) => toBuffer(c, 10)),
        toBuffer("EUR"),
        await user.account(),
      );
    }

    for (const m of mapping) {
      const bank = banks[m.bank];
      const correspondent = banks[m.correspondent];
      const user = countryUsers[bank.country];
      const countryAddress = await g.root.getCountry(
        user.call(),
        toBuffer(bank.country),
      );
      const country = g.countryContract.at(countryAddress);
      await country.addCorrespondent(
        user.send(),
        bank.codes.map((c) => toBuffer(c, 10)),
        toBuffer(m.ccy),
        {
          country: toBuffer(correspondent.country),
          codes: correspondent.codes.map((c) => toBuffer(c, 10)),
        },
      );
    }

    // console.log(
    //   "Bank3 correspondent bank in EUR",
    //   await g.countryFR.getCorrespondentBank(
    //     g.adminFRUser.call(),
    //     banks.bank3.codes.map((c) => toBuffer(c, 10)),
    //     toBuffer("EUR")
    //   )
    // );

    const route = await g.root.resolveRoute(
      g.adminFRUser.call(),
      toBuffer("EUR"),
      {
        country: toBuffer(banks.bank1.country),
        codes: banks.bank1.codes.map((c) => toBuffer(c, 10)),
      }, // from
      {
        country: toBuffer(banks.bank3.country),
        codes: banks.bank3.codes.map((c) => toBuffer(c, 10)),
      }, // to
    );
    // console.log("-->", JSON.stringify(route.debug, null, 2));
    console.log(
      "ROUTE EUR Bank1->Bank3",
      reformatRoute(cleanStruct(route) as any),
    );

    const route2 = await g.root.resolveRoute(
      g.adminFRUser.call(),
      toBuffer("USD"),
      {
        country: toBuffer(banks.bank3.country),
        codes: banks.bank3.codes.map((c) => toBuffer(c, 10)),
      }, // from
      {
        country: toBuffer(banks.bank1.country),
        codes: banks.bank1.codes.map((c) => toBuffer(c, 10)),
      }, // to
    );
    console.log(
      "ROUTE USD Bank3->Bank1",
      reformatRoute(cleanStruct(route2) as any),
    );

    const route3 = await g.root.resolveRoute(
      g.adminFRUser.call(),
      toBuffer("EUR"),
      {
        country: toBuffer(banks.bank1.country),
        codes: banks.bank1.codes.map((c) => toBuffer(c, 10)),
      }, // from
      {
        country: toBuffer(banks.bank2.country),
        codes: banks.bank2.codes.map((c) => toBuffer(c, 10)),
      }, // to
    );
    console.log(
      "ROUTE EUR Bank1->Bank2",
      reformatRoute(cleanStruct(route3) as any),
    );
  });
});
