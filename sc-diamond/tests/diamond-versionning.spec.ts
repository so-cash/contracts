import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Web3 from "web3";
import {
  ZeroAddress,
  ganacheProvider,
  getNewWallet,
} from "@so-cash/sc-shared/utils";

import dContracts from "../build";

import { Diamond } from "../ts-lib";
import { executioner } from "./common";

import {
  splitAuxdata,
  decode,
  AuxdataStyle,
} from "@ethereum-sourcify/bytecode-utils";
import type {
  CombinedFile,
  SmartContracts,
} from "@saturn-chain/smart-contract";
import SmartContractPackage, {
  SmartContract,
} from "@saturn-chain/smart-contract";

describe("Test how to manage diamond facet versionning", async function () {
  this.timeout(10000);
  const web3 = new Web3(ganacheProvider() as any);

  function extractCombined(
    from: SmartContracts,
    names: string[],
    rename?: { [old: string]: string },
  ): SmartContracts {
    const newCombined: CombinedFile = {
      version: from.combined.version,
      contracts: {},
    };
    names.forEach((f) => {
      const c = from.get(f);
      const newName = rename ? rename[f] || f : f;
      newCombined.contracts[`extracted-file:${newName}`] = {
        abi: c.abi,
        bin: c.bytecode,
        "bin-runtime": c.runtime,
      };
    });
    return SmartContractPackage.SmartContracts.load(newCombined);
  }

  it("Reconstruct a combined and check it works", async () => {
    const combinedOrigin = dContracts.combined;

    // console.log("original", combinedOrigin.version, Object.keys(combinedOrigin.contracts));

    const list = [
      "ISample",
      "SampleDiamond",
      "SampleDiamondReadable",
      "SampleDiamondWritable",
      "Facet1",
      "Facet2",
    ];

    const newContracts = extractCombined(dContracts, list);

    const wallet = await getNewWallet(web3, "default", true);

    const diamond = new Diamond(
      {
        combinedJson: dContracts.combined,
        rootName: "SampleDiamond",
        readableName: "SampleDiamondReadable",
        writableName: "SampleDiamondWritable",
        facetNames: ["Facet1", "Facet2"],
        initializeFunctionName: "initialize",
        initializeFunctionArgs: [10, "initial text"],
      },
      executioner(dContracts, wallet),
    );

    const d = await diamond.deploy();
    const instance = newContracts.get("ISample").at(d.rootAddress);
    const [value, text, value2] = await Promise.all([
      instance.getValue(wallet.call()),
      instance.getText(wallet.call()),
      instance.getVal(wallet.call()),
    ]);
    console.log("Values:", value, text, value2);
  });

  async function getDeployedBytecodeHash(address: string): Promise<string> {
    const bytecode = await web3.eth.getCode(address);
    const decoded = splitAuxdata(bytecode, AuxdataStyle.SOLIDITY);
    return web3.utils.keccak256(decoded[0]);
  }

  function getContractBytecodeHash(contract: SmartContract): string {
    const decoded = splitAuxdata(contract.runtime, AuxdataStyle.SOLIDITY);
    return web3.utils.keccak256(decoded[0]);
  }

  it("Test 1", async () => {
    const wallet = await getNewWallet(web3, "default", true);

    const diamond = new Diamond(
      {
        combinedJson: dContracts.combined,
        rootName: "SampleDiamond",
        readableName: "SampleDiamondReadable",
        writableName: "SampleDiamondWritable",
        facetNames: ["Facet1", "Facet2"],
        initializeFunctionName: "initialize",
        initializeFunctionArgs: [10, "initial text"],
      },
      executioner(dContracts, wallet),
    );

    const d = await diamond.deploy();
    console.log("Diamond deployed at:", d);

    // extract the deployed bytecode
    const bytecode = await web3.eth.getCode(d.facetAddresses["Facet1"]);
    // extract from the comiled version the runtime code of the facet
    const runtime = dContracts.get("Facet1").runtime;

    const decoded = splitAuxdata(bytecode, AuxdataStyle.SOLIDITY);
    const decoded2 = splitAuxdata(runtime, AuxdataStyle.SOLIDITY);
    console.log("bytecode:", decoded, web3.utils.keccak256(decoded[0]));
    console.log("runtime:", decoded2, web3.utils.keccak256(decoded[0]));

    expect(decoded[0]).to.equal(decoded2[0]);
  });

  it("identify the upgrade when the the facet changes", async () => {
    const list1 = [
      "ISample",
      "SampleDiamond",
      "SampleDiamondReadable",
      "SampleDiamondWritable",
      "Facet1",
      "Facet2",
    ];
    const list2 = [
      "ISample",
      "SampleDiamond",
      "SampleDiamondReadable",
      "SampleDiamondWritable",
      "Facet1",
      "Facet2V2",
    ];

    const wallet = await getNewWallet(web3, "default", true);

    const version1 = extractCombined(dContracts, list1);
    const diamondConfig = {
      combinedJson: version1.combined,
      rootName: "SampleDiamond",
      readableName: "SampleDiamondReadable",
      writableName: "SampleDiamondWritable",
      facetNames: ["Facet1", "Facet2"],
      initializeFunctionName: "initialize",
      initializeFunctionArgs: [10, "initial text"],
    };

    const diamond = new Diamond(diamondConfig, executioner(version1, wallet));

    const initialDeploy = await diamond.deploy();
    console.log("Diamond deployed at:", initialDeploy);

    // simulate a new version where the Facet2 is upgraded
    const version2 = extractCombined(dContracts, list2, { Facet2V2: "Facet2" });
    diamondConfig.combinedJson = version2.combined;

    const newDiamond = await Diamond.fromAddress(
      diamondConfig,
      initialDeploy.rootAddress,
      executioner(version2, wallet),
    );

    // console.log("Existing diamond facets", newDiamond.deployedAt);

    // get the hash of the bytecode for all facets
    const facetsHashes = await Promise.all(
      Object.entries(newDiamond.deployedAt.facetAddresses).map(
        async ([name, address]) => {
          const contract = version2.get(name);
          const hash = await getDeployedBytecodeHash(address);
          return {
            name,
            hash,
            expectedHash: getContractBytecodeHash(contract),
          };
        },
      ),
    );
    const facetsToReplace = facetsHashes.filter(
      (f) => f.hash !== f.expectedHash,
    );
    console.log("Facets hashes to replace", facetsToReplace);
    await newDiamond.upgrade(
      ...facetsToReplace.map((f) => ({ facet: f.name, withFacet: f.name })),
    );
    console.log("New Diamond after upgrade:", newDiamond.deployedAt);

    // try to rollback the upgrade by setting the old facet addresses
    // construct a replacement based on olde address vs current ones
    const replacements = Object.entries(newDiamond.deployedAt.facetAddresses)
      .map(([name, address]) => {
        if (address != initialDeploy.facetAddresses[name])
          return { facet: name, withFacet: initialDeploy.facetAddresses[name] };
        else return undefined;
      })
      .filter((r) => !!r) as { facet: string; withFacet: string }[];
    await newDiamond.upgrade(...replacements);
    console.log("Rollbacked diamond after upgrade", newDiamond.deployedAt);

    // try to remove Facet 1
    await newDiamond.upgrade({ facet: "Facet1", withFacet: ZeroAddress });
    console.log("Diamond after removing the facet", newDiamond.deployedAt);
  });
});
