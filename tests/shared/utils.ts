import { EventData } from "web3-eth-contract";
import Ganache from "ganache";
import Web3Functions from "@saturn-chain/web3-functions";
import {
  CallSendFunction,
  DeployCallbackFunction,
  EthProviderInterface,
  SendOptions,
} from "@saturn-chain/dlt-tx-data-functions";
import { EventReceiver } from "@saturn-chain/smart-contract";
import Web3 from "web3";
const { Web3FunctionProvider } = Web3Functions;

const ZeroAddress = "0x0000000000000000000000000000000000000000";

export const blockGasLimit = 80_000_000;
// export const GanacheOptions : ProviderOptions = { default_balance_ether: 1000, gasLimit: blockGasLimit, chain: {vmErrorsOnRPCResponse:true, allowUnlimitedInitCodeSize: true, allowUnlimitedContractSize: true}, logging: {quiet:true} };
export function ganacheProvider() {
  return Ganache.provider({
    wallet: { defaultBalance: 1000 },
    miner: { blockGasLimit: blockGasLimit },
    chain: {
      vmErrorsOnRPCResponse: true,
      allowUnlimitedInitCodeSize: true,
      allowUnlimitedContractSize: true,
    },
    logging: { quiet: true, debug: true, verbose: false },
  });
}
const mapAddress = new Map<string, string>();
map(ZeroAddress, "@Zero");
export function map(address: string, name: string): void {
  mapAddress.set(address, name);
}

let addressUsed = 0;

export async function getNewWallet(
  web3: Web3,
  name: string,
  reset: boolean = false,
): Promise<EthProviderInterface> {
  if (reset) addressUsed = 0;
  const accounts = await web3.eth.getAccounts();
  const address = accounts[addressUsed++];
  map(address, name);
  return new DLTInterfaceEx(web3.currentProvider, address);
}

export function traceEventLog(prefix?: string): (log: EventData) => void {
  return traceEventLogActual.bind(undefined, prefix);
}

function traceEventLogActual(prefix: string | undefined, log: EventData) {
  if (!log.event) return;
  const params = cleanEvent(log).returnValues;
  for (const key of Object.keys(params)) {
    if (Number.isInteger(Number.parseInt(key))) delete params[key];
    if (mapAddress.has(params[key])) params[key] = mapAddress.get(params[key]);
  }
  if (mapAddress.has(log.address))
    log.address = mapAddress.get(log.address) || "undefined";
  const paramsTxt = Object.keys(params)
    .map((f) => `${f}:${params[f]}`)
    .join(", ");
  console.log(
    `LOG: ${prefix ? prefix + ": " : ""}${log.blockNumber}/${log.transactionIndex}/${log.logIndex} ${
      log.address
    }.${log.event}(${paramsTxt})`,
  );
}

export async function getLogs(ev: EventReceiver): Promise<EventData[]> {
  return new Promise((resolve, reject) => {
    const logs: EventData[] = [];
    ev.on("log", (log: EventData) => logs.push(log));
    ev.on("error", reject);
    ev.on("completed", () => resolve(logs));
  });
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
    console.log("Recipient Info", r);

    return r;
  } else {
    return {
      account: ZeroAddress,
      bic: Buffer.alloc(11),
      iban: Buffer.alloc(32),
    };
  }
}

/** Create a EthProviderInterface that forces the testing of the gas and handle errors as best as possible */
export class DLTInterfaceEx extends Web3FunctionProvider {
  constructor(provider: any, address: string) {
    super(provider, () => Promise.resolve(address));
  }

  send(options: SendOptions = { maxGas: 5_000_000 }): CallSendFunction {
    // TODO: There is a bug in the test function that do not handle the 0x string value the same way as the send function - so force the conversion to bigint
    if (
      typeof options.amount === "string" &&
      (options.amount as string).startsWith("0x")
    )
      options.amount = BigInt(options.amount);
    const test = super.test({ ...options, maxGas: 5_000_000 }); // force a maximun of gas for the test as it will run on the local node
    const super_send = super.send.bind(this);
    return async (target: string, data: string) => {
      try {
        // try calling the function with the maximum gas on the local node and catch any error and retrieve the gas used
        const res = await test(target, data);
        const gas = res.result; // TODO: Could record the gas somewhere for stats ?
        const send = super_send({ ...options, maxGas: gas });
        return await send(target, data);
      } catch (error) {
        throw new Error("DLT tx failed: " + (error as Error).message);
      }
    };
  }

  newi(options: SendOptions = { maxGas: 5_000_000 }): DeployCallbackFunction {
    // TODO: There is a bug in the test function that do not handle the 0x string value the same way as the send function - so force the conversion to bigint
    if (
      typeof options.amount === "string" &&
      (options.amount as string).startsWith("0x")
    )
      options.amount = BigInt(options.amount);
    const test = super.test({ ...options, maxGas: 5_000_000 }); // force a maximun of gas for the test as it will run on the local node
    const super_newi = super.newi.bind(this);
    return async (name: string, bytecode: string) => {
      try {
        // try deploying the bytecode with the maximum gas on the local node and catch any error and retrieve the gas used
        //  Smart contract deployment cost (ref: https://www.rareskills.io/post/smart-contract-creation-cost)
        // The 21,000 gas that all Ethereum transactions must pay
        // A fixed cost of 32,000 gas for creating a new contract
        // 22,100 for each storage variable set
        // 4 gas for each zero byte in the transaction data 16 gas for each non-zero byte in the transaction.
        // The cost to execute each bytecode during the initialization
        // 200 gas per byte of deployed bytecode
        const res = await test(ZeroAddress, bytecode);
        // console.log("Deployed with gas: "+res.result);
        let gas = 21_000 + 32_000; // base cost
        gas += res.result; // add the gas used for the deployment
        const slicing = bytecode.startsWith("0x") ? 2 : 0;
        const code = Buffer.from(bytecode.slice(slicing), "hex");
        gas += 200 * code.length; // add a gas for the code size
        // console.log("Final Deployed with gas: "+gas, code.length, code.length*200);

        const newi = super_newi({ ...options, maxGas: gas });
        return await newi(name, bytecode);
      } catch (error) {
        throw new Error("DLT deploy failed: " + (error as Error).message);
      }
    };
  }
}

function cleanValue(v: any): any {
  if (v instanceof Buffer) return v.toString("hex");
  if (typeof v === "object") {
    const res: Record<string, any> = {};
    for (const key of Object.keys(v)) {
      res[key] = cleanValue(v[key]);
    }
    return res;
  }
  if (Array.isArray(v)) return v.map(cleanValue);
  return v;
}

export function cleanEvent(ev: EventData): EventData {
  const res: EventData = { ...ev };
  res.returnValues = cleanStruct(ev.returnValues);
  return res;
}
export function cleanStruct(s: any): Record<string, any> {
  const res: Record<string, any> = {};
  if (s && typeof s === "object") {
    for (const key of Object.keys(s)) {
      if (Number.isNaN(Number.parseInt(key))) {
        if (typeof s[key] === "object") res[key] = cleanStruct(s[key]);
        else res[key] = cleanValue(s[key]);
      }
    }
  }
  return res;
}
