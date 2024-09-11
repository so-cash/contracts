import Web3 from "web3";
import crypto from "crypto";
import {
  SmartContractInstance,
  SmartContracts,
} from "@saturn-chain/smart-contract";
import { sha256 } from "js-sha256";
import { EthProviderInterface } from "@saturn-chain/dlt-tx-data-functions";
import soCashContracts from "../../build";
import { blockTimestamp } from "./dates";
import { map } from "./utils";

export const contractsNames = {
  cash: {
    bank: "SoCashBank",
    account: "SoCashAccount",
    ibanCalc: "IBANCalculator",
  },
  amm: {
    amm: "CPAMM",
    iBank: "ISoCashBank",
    iAccount: "ISoCashOwnedAccount",
  },
  cashPooling: {
    cashPool: "SoCashPooling",
  },
};

export function checkContractCompilation(
  contracts: SmartContracts,
  contractsNames: { [key: string]: string }
) {
  for (const contractName of Object.values(contractsNames)) {
    if (!contracts.get(contractName)) {
      throw new Error(`Contract ${contractName} not found`);
    }
  }
}

export async function createAccount(
  name: string,
  inBank: SmartContractInstance,
  owner: EthProviderInterface
): Promise<SmartContractInstance> {
  const accountContract = soCashContracts.get(contractsNames.cash.account);
  const account = await accountContract.deploy(owner.newi(), name);
  map(account.deployedAt, name);
  await account.transferOwnership(owner.send(), inBank.deployedAt);
  await inBank.registerAccount(owner.send(), account.deployedAt);
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
