import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  cleanStruct,
  ganacheProvider,
  getLogs,
  getNewWallet,
} from "@so-cash/sc-shared/utils";

import combined from "../build/combined.json" assert { type: "json" };
import dContracts from "../build";

import {
  Diamond,
  CombinedFile,
  IExecutioner,
  CompiledSmartContract,
} from "../ts-lib";

function executioner(
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
      return instance[funct](wallet.send(), ...args);
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

describe("Deploy Sample Diamond", async function () {
  this.timeout(10000);
  const web3 = new Web3(ganacheProvider() as any);

  it("Deploy Sample Diamond", async () => {
    const wallet = await getNewWallet(web3, "default", true);

    const diamond = new Diamond(
      {
        combinedJson: combined as CombinedFile,
        rootName: "SampleDiamond",
        readableName: "SampleDiamondReadable",
        writableName: "SampleDiamondWritable",
        facetNames: ["Facet1", "Facet2"],
        initializeFunctionName: "initialize",
        initializeFunctionArgs: [10, "initial text"],
      },
      executioner(wallet),
    );

    const d = await diamond.deploy();
    console.log("Diamond deployed at:", d);

    // read the values
    const facet1 = dContracts.get("IFacet1").at(d.rootAddress);
    const facet2 = dContracts.get("IFacet2").at(d.rootAddress);
    const [value, text, value2] = await Promise.all([
      facet1.getValue(wallet.call()),
      facet2.getText(wallet.call()),
      facet2.getVal(wallet.call()),
    ]);
    console.log("Values:", value, text, value2);
    expect(Number.parseInt(value)).to.equal(10);
    expect(text).to.equal("initial text");
    expect(Number.parseInt(value2)).to.equal(0);

    // load the diamond from address
    const newDiamond = await Diamond.fromAddress(
      {
        combinedJson: combined as CombinedFile,
        rootName: "SampleDiamond",
        readableName: "SampleDiamondReadable",
        writableName: "SampleDiamondWritable",
      },
      d.rootAddress,
      executioner(wallet),
    );
    console.log("New Diamond:", newDiamond.deployedAt);

    // upgrade the diamond with the new facets, will deploy new instances and replace the seletors of the old ones
    await newDiamond.upgrade(
      { facet: "Facet1", withFacet: "Facet1" },
      { facet: "Facet2", withFacet: "Facet2V2" },
      // {facet:"Facet2", withFacet: "Facet2"},
    );
    console.log(
      "New Diamond after upgrade:",
      newDiamond.deployedAt,
      JSON.stringify(newDiamond.facets, null, 2),
    );
  });
});
