import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import { EthProviderInterface } from "@saturn-chain/dlt-tx-data-functions";
import Web3Functions from "@saturn-chain/web3-functions";
const { Web3FunctionProvider } = Web3Functions;
import {
  EventReceiver,
  SmartContract,
  SmartContractInstance,
  SmartContracts,
} from "@saturn-chain/smart-contract";
import Ganache from "ganache";

import Iban from "iban";

import allContracts from "../build";
import { ganacheProvider, traceEventLog } from "./shared";

describe("Test the IBAN calculations", function () {
  this.timeout(10000);
  let web3: Web3;
  let bank1address: string;
  let Contract: SmartContract;
  let instance: SmartContractInstance;
  let bank1: EthProviderInterface;
  let eventSub: EventReceiver;

  const contractName = "IBANCalculator";

  before(async () => {
    web3 = new Web3(ganacheProvider() as any as any);
    //web3 = new Web3("ws://localhost:8546");

    bank1address = (await web3.eth.getAccounts())[0];
    bank1 = new Web3FunctionProvider(web3.currentProvider, () =>
      Promise.resolve(bank1address),
    );

    if (allContracts.get(contractName)) {
      Contract = allContracts.get(contractName)!;
      instance = await Contract.deploy(
        bank1.newi({ maxGas: 3000000 }) /* possibly add params later */,
      );

      eventSub = instance.allEvents(bank1.sub(), {});
      eventSub.on("log", traceEventLog());
    } else {
      throw new Error(
        contractName + " contract not defined in the compilation result",
      );
    }
  });

  after(() => {
    if (eventSub) eventSub.removeAllListeners();
  });

  it("Test the iban js lib first", () => {
    console.log("French spec", Iban.countries["FR"]);
    console.log(
      "Calculate IBAN",
      "Account:",
      "20041010050500013M02606",
      "IBAN:",
      Iban.fromBBAN("FR", "20041010050500013M02606"),
    );
  });

  it("Calculate RIB Key", async () => {
    let key = await instance.frenchRIBKey(bank1.call(), 1, 2, 3);
    expect(key).to.equal("66");

    key = await instance.frenchRIBKey(bank1.call(), 10000, 20000, 33333333333);
    expect(key).to.equal("89");
  });

  it("Calculate the value of a string", async () => {
    const test =
      "001234567890ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz;=.";
    const asNumber = IbanFakeBigNum(test);
    const fromSc = await instance.frenchStringToNumber(bank1.call(), test);
    console.log("Test string", test, asNumber, fromSc);
    expect(fromSc).equal(asNumber);
  });

  it("Calculate the BBAN", async () => {
    const bankCode = "20041";
    const branchCode = "1005";
    const accountNumber = "00013M02600";

    const key = await instance.frenchRIBKey(
      bank1.call(),
      IbanFakeBigNum(bankCode),
      IbanFakeBigNum(branchCode),
      IbanFakeBigNum(accountNumber),
    );
    const bban =
      padWithZeros(bankCode, 5) +
      padWithZeros(branchCode, 5) +
      padWithZeros(accountNumber, 11) +
      padWithZeros(key, 2);

    const bbanSc = await instance.frenchBBAN(
      bank1.call(),
      bankCode,
      branchCode,
      accountNumber,
    );
    console.log(
      "Calculate BBAN",
      "Bank:",
      bankCode,
      "Branch:",
      branchCode,
      "Account:",
      accountNumber,
      "Key:",
      key,
      "BBAN:",
      bban,
      "BBAN SC:",
      bbanSc,
    );
    expect(bbanSc).equal(bban);
  });

  it("Calculate the IBAN from a BBAN", async () => {
    const bban = "200410100500013M0260005";
    const iban = Iban.fromBBAN("FR", bban);
    const cle = ibanCalculerCle("FR", bban);
    // const num = ibanConvertirLettres("ABCDZ");
    // const numSc = await instance.ibanStringToNumber(bank1.call(), "ABCDZ");
    // console.log("Intermediary num:", num, numSc);

    const ibanSc = await instance.calculateIBAN(bank1.call(), "FR", bban);
    console.log(
      "Calculate IBAN",
      "BBAN:",
      bban,
      "Cle:",
      cle,
      "IBAN:",
      iban,
      "IBAN SC:",
      ibanSc,
    );
    expect(ibanSc).equal(iban);
  });

  it("Calculate a french IBAN", async () => {
    const bankCode = "20041";
    const branchCode = "1005";
    const accountNumber = "00013M02600";

    const key = await instance.frenchRIBKey(
      bank1.call(),
      IbanFakeBigNum(bankCode),
      IbanFakeBigNum(branchCode),
      IbanFakeBigNum(accountNumber),
    );
    const bban =
      padWithZeros(bankCode, 5) +
      padWithZeros(branchCode, 5) +
      padWithZeros(accountNumber, 11) +
      padWithZeros(key, 2);

    const iban = Iban.fromBBAN("FR", bban);

    const ibanSc = await instance.calculateFrenchIBAN(
      bank1.call(),
      bankCode,
      branchCode,
      accountNumber,
    );

    console.log(
      "Calculate French IBAN",
      "Bank:",
      bankCode,
      "Branch:",
      branchCode,
      "Account:",
      accountNumber,
      "IBAN:",
      iban,
      "IBAN SC:",
      ibanSc,
    );
    expect(ibanSc).equal(iban);
  });

  it("Reverse calculation from IBAN to French details", async () => {
    const iban = "FR29200410100500013M0260005";
    const details = await instance.extractFrenchIBAN(bank1.call(), iban);

    console.log(
      "Reverse calculation from IBAN to French details",
      "IBAN:",
      iban,
      "Details:",
      details,
    );

    expect(details.bankCode5).equal("20041");
    expect(details.branchCode5).equal("01005");
    expect(details.accountNumber11).equal("00013M02600");
    expect(details.ribKey).equal("5");
  });

  it("Validate specific cases", async () => {
    // extract value of a test IBAN
    const iban = "FR7630002057280000000000157";
    const details = await instance.extractFrenchIBAN(bank1.call(), iban);
    console.log(
      "Reverse calculation from IBAN to French details",
      "IBAN:",
      iban,
      "Details:",
      details,
    );
  });
});

// algos in js to test the contract

function padWithZeros(str: string, length: number): string {
  return str.padStart(length, "0");
}

function IbanFakeBigNum(s: string): string {
  let leadingZeros = true;
  return Array.from(Uint8Array.from(Buffer.from(s)))
    .map((c, i) => {
      const r = IbanStringToNumber(String.fromCharCode(c));
      if (c == 48 && leadingZeros) return "";
      else leadingZeros = false;
      if (c == 48 && r == 0) return "0";
      else if (r > 0) return `${r}`;
      else return "";
    })
    .join("");
}

function IbanStringToNumber(s: string): number {
  let result = 0;
  for (let i = 0; i < s.length; i++) {
    let c = s.charCodeAt(i) - 48;
    if (c >= 0 && c <= 9) {
      result = result * 10 + c;
    } else {
      if (c >= 97 - 48 && c <= 122 - 48)
        // a-z
        c -= 97 - 65; // make uppercase
      if (c >= 17 && c <= 34)
        // A-R
        c = ((c - 17) % 9) + 1;
      else if (c >= 35 && c <= 42)
        // S-Z
        c = ((c - 16) % 9) + 1;
      else c = 0; // ignore other characters
      if (c > 0) result = result * 10 + c;
    }
  }
  return result;
}

// -----------------------------------------------
// I B A N
// -----------------------------------------------
function ibanFormater(texte: string) {
  var texte = texte == null ? "" : texte.toString().toUpperCase();
  return texte;
}

// -----------------------------------------------
function ibanConvertirLettres(texte: string) {
  let texteConverti = "";

  for (let i = 0; i < texte.length; i++) {
    const caractere = texte.charAt(i);
    if (caractere > "9") {
      if (caractere >= "A" && caractere <= "Z") {
        texteConverti += (caractere.charCodeAt(0) - 55).toString();
      }
    } else if (caractere >= "0") {
      texteConverti += caractere;
    }
  }
  return texteConverti;
}

// -----------------------------------------------
function ibanCalculerCle(pay: string, bban: string): string {
  var numero = ibanConvertirLettres(bban.toString() + pay) + "00";
  var calculCle = 0;
  var pos = 0;
  while (pos < numero.length) {
    calculCle = parseInt(calculCle.toString() + numero.substr(pos, 9), 10) % 97;
    pos += 9;
  }
  calculCle = 98 - (calculCle % 97);
  var cle = (calculCle < 10 ? "0" : "") + calculCle.toString();
  return cle;
}
