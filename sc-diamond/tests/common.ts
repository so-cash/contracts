import {
  cleanStruct,
  ganacheProvider,
  getLogs,
  getNewWallet,
} from "@so-cash/sc-shared/utils";
import { CompiledSmartContract, IExecutioner } from "../ts-lib";
import { SmartContracts } from "@saturn-chain/smart-contract";

export function executioner(
  dContracts: SmartContracts,
  wallet: Awaited<ReturnType<typeof getNewWallet>>,
): IExecutioner {
  return {
    deployer: async (
      name: string,
      contract: CompiledSmartContract,
      flags: { isFacet?: boolean; isUpgrade?: boolean },
      ...args: any[]
    ) => {
      const sc = dContracts.get(name);
      const instance = await sc.deploy(wallet.newi(), ...args);
      return instance.deployedAt;
    },
    executer: async (
      name: string,
      contract: CompiledSmartContract,
      target: string,
      funct: string,
      ...args: any[]
    ) => {
      const sc = dContracts.get(name);
      const instance = sc.at(target);
      const tx = await instance[funct](wallet.send(), ...args);
      console.log("SEND", instance.deployedAt, funct, "(", ...args, ") =>", tx);

      return tx;
    },
    reader: async (
      name: string,
      contract: CompiledSmartContract,
      target: string,
      funct: string,
      ...args: any[]
    ) => {
      const sc = dContracts.get(name);
      const instance = sc.at(target);
      return instance[funct](wallet.call(), ...args);
    },
  };
}
