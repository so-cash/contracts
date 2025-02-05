import Web3 from "web3";
import { sha256 } from "js-sha256";
import crypto from "crypto";
import {
  SmartContractInstance,
  SmartContracts,
} from "@saturn-chain/smart-contract";
import { EthProviderInterface } from "@saturn-chain/dlt-tx-data-functions";
import soCashContracts from "@so-cash/sc-so-cash";
import { blockTimestamp } from "./dates";
import { ZeroAddress, map, toBuffer } from "./utils";

export const contractsNames = {
  cash: {
    bank: "SoCashBank",
    account: "SoCashAccount",
    fxProvider: "SoCashFXProvider",
    ibanCalc: "IBANCalculator",
    paymentEngine: "PaymentEngine",
    sharedFunctions: "SharedFunctions",
  },
  amm: {
    amm: "CPAMM",
    iBank: "ISoCashBank",
    iAccount: "ISoCashOwnedAccount",
  },
  ref: {
    root: "RootReferential",
    country: "CountryReferential",
    stablecoin: "Stablecoin",
  },
  cashPooling: {
    cashPool: "SoCashPooling",
  },
};

export function checkContractCompilation(
  contracts: SmartContracts,
  contractsNames: { [key: string]: string },
) {
  for (const contractName of Object.values(contractsNames)) {
    if (!contracts.get(contractName)) {
      throw new Error(`Contract ${contractName} not found`);
    } else {
      // console.log(`Contract ${contractName} found`);
    }
  }
}

export async function createAccount(
  name: string,
  inBank: SmartContractInstance,
  owner: EthProviderInterface,
  forBank?: SmartContractInstance,
): Promise<SmartContractInstance> {
  const accountContract = soCashContracts.get(contractsNames.cash.account);
  const account = await accountContract.deploy(owner.newi(), name);
  map(account.deployedAt, name);
  await account.transferOwnership(owner.send(), inBank.deployedAt);
  await inBank.registerAccount(owner.send(), account.deployedAt);
  if (forBank) {
    // link the account to the bank for which this account is a nostro
    await account.setAttributeAddr(
      owner.send(),
      toBuffer("soCashBank"),
      forBank.deployedAt,
    );
    await account.whitelist(owner.send(), forBank.deployedAt);
  }
  return account;
}

export async function createHTLCData() {
  const secret = crypto.randomBytes(32).toString("hex");
  const cancelSecret = crypto.randomBytes(32).toString("hex");
  const hash = "0x" + (sha256(secret) || "");
  const cancelHash = "0x" + (sha256(cancelSecret) || "");
  const tradeId = crypto.randomUUID();
  const blockTime = await blockTimestamp();
  const timeout = blockTime + 120; // 2 minute
  const id = ""; // to be filled later
  return { id, secret, cancelSecret, hash, cancelHash, tradeId, timeout };
}

export function receipientInfo(account?: string, bic?: string, iban?: string) {
  if (account)
    return { account, bic: Buffer.alloc(11), iban: Buffer.alloc(32) };
  if (bic || iban) {
    let buff = Buffer.alloc(32);
    Buffer.from(iban || "").copy(buff, 0);
    const r = {
      account: ZeroAddress,
      bic: bic
        ? Buffer.from(`${bic}           `.slice(0, 11))
        : Buffer.alloc(11),
      iban: buff,
    };
    // console.log("Recipient Info", { account, bic, iban }, r);

    return r;
  } else {
    return {
      account: ZeroAddress,
      bic: Buffer.alloc(11),
      iban: Buffer.alloc(32),
    };
  }
}

export function bankIdentifier(country: string, codes: string[]) {
  return {
    country: toBuffer(country, 2),
    codes: codes.map((c) => toBuffer(c, 10)),
  };
}

export function bankAccountSoCash(
  bank: SmartContractInstance,
  account: SmartContractInstance,
) {
  return {
    model: 1,
    bank: bank.deployedAt,
    account: account.deployedAt,
  };
}

export function bankAccountERC20(
  bank: SmartContractInstance,
  account?: string,
) {
  return {
    model: 2,
    bank: bank.deployedAt,
    account: account || ZeroAddress,
  };
}
