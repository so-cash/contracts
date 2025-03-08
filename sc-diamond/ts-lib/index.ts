/**
 * @packageDocumentation
 * @module sc-diamond
 * This typescript library is used to facilitate the preparation of diamond deployment with its facets
 */
import { ZeroAddress } from "@so-cash/sc-shared/utils";
import AbiCoder from "web3-eth-abi";
import Utils, { AbiItem } from "web3-utils";
// fix the lib issue which type declares jsonInterfaceMethodToString but really it exports the function as _jsonInterfaceMethodToString
const jsonInterfaceMethodToString: typeof Utils.jsonInterfaceMethodToString = (
  Utils as any
)._jsonInterfaceMethodToString;

export interface CompiledSmartContract {
  abi: AbiItem[];
  bin: string;
  "bin-runtime": string;
}
export type ContractFullName = `${string}:${string}`;
export type CompiledSmartContractDict = {
  [fullName: ContractFullName]: CompiledSmartContract;
};
export interface CombinedFile {
  contracts: CompiledSmartContractDict;
  version: string;
}

interface ContractInfos {
  name: string;
  fullName: ContractFullName;
  hasCode: boolean;
}
interface InternalCombinedFile extends CombinedFile {
  names: Map<string, ContractInfos>; // contract or library name to full name (file:contract)
  selectorContractMapping: Map<string, string[]>; // selector to list of contract names that have this selector
  functions: Map<string, string>; // function signature to function name
  contractSelectors: Map<string, string[]>; // contract name to list of selectors
}

export enum FacetCutAction {
  Add,
  Replace,
  Remove,
  All, // used only for the initialization, not accepted elsewhere
}

export interface FacetFunction {
  selector: string;
  fullName?: string;
}

export interface FacetFunctionWithTarget extends FacetFunction {
  target: string;
}

// the type returned by the readble facets() function of the diamond
export interface RawFacet {
  target: string;
  selectors: string[];
}

export interface Facet {
  target: string;
  functions: FacetFunction[];
  name?: string;
}

export interface DiamondCut {
  target: string;
  action: FacetCutAction;
  selectors: string[];
}

export interface DiamondBaseConfig {
  combinedJson: CombinedFile;
  rootName: string;
  readableName: string;
  writableName: string;
}

export interface DiamondCreateConfig extends DiamondBaseConfig {
  facetNames: string[];
  initializeFunctionName: string;
  initializeFunctionArgs: any[];
}

export interface IExecutioner {
  deployer: (
    name: string,
    contract: CompiledSmartContract,
    flags: { isFacet?: boolean; isUpgrade?: boolean },
    ...args: any[]
  ) => Promise<string>;
  executer: (
    name: string,
    contract: CompiledSmartContract,
    target: string,
    funct: string,
    ...args: any[]
  ) => Promise<string>;
  reader: (
    name: string,
    contract: CompiledSmartContract,
    target: string,
    funct: string,
    ...args: any[]
  ) => Promise<any>;
}

export interface DeployedDiamond {
  rootAddress: string;
  facetAddresses: { [name: string]: string };
}
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

//
function resolvePreference(
  fullName1: string,
  fullName2: string,
  duplicatePref: RegExp[],
): string {
  for (const pref of duplicatePref) {
    if (pref.test(fullName1)) return fullName1;
    if (pref.test(fullName2)) return fullName2;
  }
  return fullName1;
}

/** Function to pre process the combined file so that getting the selectors, functions, contract are easier */
function prepareCombined(
  combined: CombinedFile,
  duplicatePref: RegExp[] = [],
): InternalCombinedFile {
  const names = new Map<string, ContractInfos>();
  const selectorContractMapping = new Map<string, string[]>();
  const functions = new Map<string, string>();
  const contractSelectors = new Map<string, string[]>();
  for (const fullName of Object.keys(
    combined.contracts,
  ) as ContractFullName[]) {
    const [_, name] = fullName.split(":");
    // check if the contract is already with this name
    if (names.has(name)) {
      // resolve the preference
      const existingFullName = names.get(name)!.fullName;
      const preferred = resolvePreference(
        existingFullName,
        fullName,
        duplicatePref,
      );
      // if we prefer keeping the existing one we skip the new one
      if (preferred === existingFullName) continue;
    }
    // maps the contract name to its full name
    names.set(name, {
      name,
      fullName,
      hasCode: combined.contracts[fullName].bin.length > 2,
    });
    // get the contract in the combined file
    const contract = combined.contracts[fullName];
    // extract only the functions from the contract (selector and actual function name)
    const contractFunctions = contract.abi
      .filter((abi) => abi.type === "function")
      .map<FacetFunction>((abi) => ({
        selector: AbiCoder.encodeFunctionSignature(abi),
        fullName: jsonInterfaceMethodToString(abi),
      }));
    // build the mapping of selector to the contracts that have this selector
    contractFunctions.forEach((func) => {
      if (selectorContractMapping.has(func.selector)) {
        selectorContractMapping.get(func.selector)!.push(name);
      } else {
        selectorContractMapping.set(func.selector, [name]);
      }
      if (func.fullName) functions.set(func.selector, func.fullName);
    });
    // build the mapping of contract to its selectors
    contractSelectors.set(
      name,
      contractFunctions.map((func) => func.selector),
    );
  }

  return {
    ...combined,
    names, // contract or library name to full name (file:contract)
    selectorContractMapping, // selector to list of contract names that have this selector
    functions, // function signature to function name
    contractSelectors, // contract name to list of selectors
  };
}

// init function in the same order as the FacetCutActions Add, Replace, Remove, All
const initFunctions: string[] = [
  "__initAdd",
  "__initReplace",
  "__initRemove",
  "__init",
];

export class Diamond {
  protected _deployedAt?: DeployedDiamond;
  protected _facets?: Facet[];
  protected internalCombined: InternalCombinedFile;
  constructor(
    private config: DiamondCreateConfig,
    private executioner: IExecutioner,
    duplicatePref: RegExp[] = [],
  ) {
    this.internalCombined = prepareCombined(config.combinedJson, duplicatePref);
  }

  protected async loadFacets(facets?: RawFacet[]) {
    if (!facets && this._deployedAt?.rootAddress) {
      // no facets provided, load from the deployed diamond
      facets = await await this.executioner.reader(
        this.config.readableName,
        this.getContract(this.config.readableName),
        this._deployedAt.rootAddress,
        "facets",
      );
    }
    if (!facets) {
      throw new Error("Facets not provided and not diamond not deployed yet");
    }
    this._facets = facets.map((facet: RawFacet) => ({
      target: facet.target,
      functions: facet.selectors.map((selector: string) => ({
        selector,
        fullName:
          this.internalCombined.functions.get(selector) ||
          `NoName_${selector}()`,
      })),
      name:
        this.findBestContractNameBySelectors(facet.selectors, true) ||
        `Unknown_${facet.target.slice(2, 10)}`,
    }));
    // update the config to avoid error in case of new deployment
    this.config.facetNames = this._facets
      .map((facet) => facet.name!)
      .filter(
        (name) =>
          name &&
          name !== this.config.readableName &&
          name !== this.config.writableName,
      );
    if (this._deployedAt) {
      this._deployedAt.facetAddresses = this._facets.reduce<{
        [name: string]: string;
      }>((acc, facet) => {
        acc[facet.name!] = facet.target;
        return acc;
      }, {});
    }
  }

  static async fromAddress(
    config: DiamondBaseConfig,
    rootAddress: string,
    exec: IExecutioner,
  ): Promise<Diamond> {
    const internalCombined = prepareCombined(config.combinedJson);
    // first collect the facet addresses
    const facets: RawFacet[] = await exec.reader(
      config.readableName,
      Diamond.getContractFromCombined(internalCombined, config.readableName),
      rootAddress,
      "facets",
    );
    // console.log("Facets", facets);

    const self = new Diamond(
      {
        ...config,
        facetNames: facets.map((facet: any) => facet.target),
        initializeFunctionName: "",
        initializeFunctionArgs: [],
      },
      exec,
    );

    self.loadFacets(facets);

    self._deployedAt = {
      rootAddress,
      facetAddresses: self._facets!.reduce<{ [name: string]: string }>(
        (acc, facet) => {
          acc[facet.name!] = facet.target;
          return acc;
        },
        {},
      ),
    };

    return self;
  }

  get deployedAt(): DeployedDiamond {
    if (!this._deployedAt) {
      throw new Error("Diamond not yet deployed");
    }
    return this._deployedAt;
  }

  get facets(): Facet[] {
    if (!this._facets) {
      throw new Error("Diamond Facets not yet knwon");
    }
    return this._facets;
  }

  protected static getContractFromCombined(
    combined: InternalCombinedFile,
    name: string,
    backup?: string,
  ): CompiledSmartContract {
    const fullName: ContractFullName =
      combined.names.get(name)?.fullName || (name as ContractFullName);
    const contract = combined.contracts[fullName];
    if (!contract) {
      if (backup) {
        return Diamond.getContractFromCombined(combined, backup);
      }
      throw new Error(`Contract ${name} not found in combined json`);
    }
    return contract;
  }

  hasContract(name: string, backup?: string): boolean {
    return (
      this.internalCombined.names.has(name) ||
      (!!backup && this.internalCombined.names.has(backup))
    );
  }

  getContract(name: string, backup?: string): CompiledSmartContract {
    const contract = Diamond.getContractFromCombined(
      this.internalCombined,
      name,
      backup,
    );
    return contract;
  }

  protected buildInitializeData(): string {
    // find the contract initialize function
    const contract = this.getContract(this.config.writableName);
    const initializeFunction = contract.abi.find(
      (abi) =>
        abi.name === this.config.initializeFunctionName &&
        abi.type === "function",
    );
    if (!initializeFunction) {
      throw new Error(
        `Initialize function ${this.config.initializeFunctionName} not found in contract ${this.config.writableName}`,
      );
    }
    // encode the data
    return AbiCoder.encodeFunctionCall(
      initializeFunction,
      this.config.initializeFunctionArgs,
    );
  }

  protected listAbiSelectors(contract: CompiledSmartContract): string[] {
    // console.log("List ABI Selectors:", contract.abi.map(abi=>`\n${abi.type}: ${abi.name}`));

    return contract.abi
      .filter((abi) => abi.type === "function")
      .filter((abi) => !initFunctions.includes(abi.name!)) // remove the init functions that are not intended to be exposed
      .map((abi) => AbiCoder.encodeFunctionSignature(abi));
  }

  protected getContractFunction(
    contractName: string,
    functionName: string,
  ): AbiItem | undefined {
    const info = this.internalCombined.names.get(contractName);
    if (!info) return undefined;
    const abi = this.internalCombined.contracts[info.fullName]?.abi;
    if (!abi) return undefined;
    return abi.find((abi) => abi.name === functionName);
  }

  protected functionEncode(
    contractName: string,
    functionName: string,
    args: any[],
  ): string {
    const funcAbi = this.getContractFunction(contractName, functionName);
    if (!funcAbi)
      throw new Error(
        `Function ${functionName} not found in contract ${contractName}`,
      );
    return AbiCoder.encodeFunctionCall(funcAbi, args);
  }

  protected findBestContractNameBySelectors(
    selectors: string[],
    onlyCode: boolean = false,
  ): string | undefined {
    const counts = new Map<string, number>();
    selectors.forEach((selector) => {
      if (this.internalCombined.selectorContractMapping.has(selector)) {
        this.internalCombined.selectorContractMapping
          .get(selector)!
          .forEach((name) => {
            if (counts.has(name)) {
              counts.set(name, counts.get(name)! + 1);
            } else {
              counts.set(name, 1);
            }
          });
      }
    });
    counts.forEach((count, name) => {
      if (onlyCode) {
        // contracts with no code (interface or abstract) have to be ignored because they cannot be facets
        if (this.internalCombined.names.get(name)?.hasCode == false)
          counts.delete(name);
      } else {
        // but if we do not ignore interfaces, at least give a bonus to contracts
        if (this.internalCombined.names.get(name)?.hasCode) count++;
        counts.set(name, count);
      }
    });
    // console.log("Find best contract name by selectors", selectors, counts.entries());

    let bestName: string | undefined;
    let bestCount = 0;

    counts.forEach((count, name) => {
      if (count > bestCount) {
        bestCount = count;
        bestName = name;
      }
    });
    return bestName;
  }

  protected async deployFacets(facetNames: string[], isUpgrade = false) {
    const facetAddresses: { [name: string]: string } = {};
    const deployments = await Promise.all(
      facetNames
        .filter((name) => this.hasContract(name))
        .map(async (name) => {
          const contract = this.getContract(name);
          const addr = await this.executioner.deployer(name, contract, {
            isFacet: true,
            isUpgrade,
          });
          return [name, addr] as [string, string];
        }),
    );
    deployments.forEach(([name, addr]) => {
      facetAddresses[name] = addr;
    });
    return facetAddresses;
  }

  async deploy(debug?: boolean): Promise<DeployedDiamond> {
    const facetAddresses = await this.deployFacets([
      ...this.config.facetNames,
      this.config.readableName,
      this.config.writableName,
    ]);
    // deploy the root contract
    const rootContract = this.getContract(this.config.rootName);

    const rootAddress = await this.executioner.deployer(
      this.config.rootName,
      rootContract,
      { isFacet: false },
      facetAddresses[this.config.readableName],
      facetAddresses[this.config.writableName],
      this.buildInitializeData(),
    );

    // now cut the diamond by adding the facets
    const diamondCut = this.config.facetNames.map<DiamondCut>((name) => ({
      target: facetAddresses[name],
      selectors: this.listAbiSelectors(this.getContract(`I${name}`, name)),
      action: FacetCutAction.Add,
    }));
    // console.log("Diamond Cut", diamondCut);
    // search for duplicates selectors in the facets and display a warning if any
    const selectors = new Map<string, string[]>();
    diamondCut.forEach((cut) => {
      const [name, target] = Object.entries(facetAddresses).find(
        ([_, v]) => v === cut.target,
      )!;
      cut.selectors.forEach((selector) => {
        if (selectors.has(selector)) {
          selectors.get(selector)!.push(name);
          console.warn(
            `WARN: Selector ${selector}:${this.internalCombined.functions.get(selector)} is present in multiple facets [${selectors.get(selector)!.join(",")}], this may lead to unexpected behavior`,
          );
        } else {
          selectors.set(selector, [name]);
        }
      });
    });
    if (debug) {
      // display the the facets and selectors names
      this.config.facetNames.forEach((name, index) => {
        console.log(
          `Facet ${name} : ${this.internalCombined.names.get(name)?.fullName} at ${facetAddresses[name]}`,
        );
        diamondCut[index].selectors.forEach((selector) => {
          console.log(
            `  - ${this.internalCombined.functions.get(selector)} - ${selector}`,
          );
        });
      });
    }

    await this.executioner.executer(
      this.config.writableName,
      this.getContract(this.config.writableName),
      rootAddress,
      "diamondCut",
      diamondCut,
      ZERO_ADDRESS,
      "0x",
    );

    this._deployedAt = {
      rootAddress,
      facetAddresses,
    };
    await this.loadFacets();
    return this._deployedAt;
  }

  async upgrade(
    ...replace: { facet: string; withFacet: string; initParams?: any[] }[]
  ): Promise<DeployedDiamond> {
    // replace is an array with the facet name to replace with a new facet name or an existing facet address
    // when the facet name has not been resolved the name is "Unknown_ABCDEF1234" where ABCDEF1234 is the first 8 characters of the address
    // when the target facet is an address, it is considered as an existing facet and will not be deployed
    // when the new facet is a new facet that did not exists, both facet and withFacet are the same
    if (!this._deployedAt || !this._deployedAt.rootAddress) {
      throw new Error("Diamond not yet deployed");
    }

    // the algo will need to identify the selectors that need to be replaced, added and removed based on this replace array
    // it will then need to call the diamondCut function with the new selectors
    // it will also need to call the __init???(...) function on the new facets that have been added or replaced or removed

    // Add the target address based on the name provided
    let withAddress = replace.map((r) => ({
      ...r,
      currentAddress: this._deployedAt!.facetAddresses[r.facet] || ZeroAddress, // can be Zero if the facet does not exist yet
      targetAddress: "", // will be resolved later
      existingSelectors: [] as FacetFunction[],
      newSelectors: [] as FacetFunction[],
    }));

    // first identify the new facets that need to be deployed
    const deployable = withAddress
      .filter((r) => !r.withFacet.startsWith("0x"))
      .filter((r) => this.hasContract(r.withFacet));

    // identify the facet that have been provided as addresses
    withAddress
      .filter((r) => r.withFacet.startsWith("0x")) // only the one that are addresses
      .forEach((r) => {
        r.targetAddress = r.withFacet;
        // use the facet name as the target name when we are not removing the target
        if (r.withFacet !== ZeroAddress) r.withFacet = r.facet;
      });

    // the facets that are not valid names or addresses will be ignored

    // deploy the new facets and set the target address
    const deployedAddress = await this.deployFacets(
      deployable.map((r) => r.withFacet),
      true,
    );
    withAddress
      .filter((f) => f.withFacet in deployedAddress) // only the one that have been deployed
      .forEach((f) => (f.targetAddress = deployedAddress[f.withFacet]));

    // all the facets now have a current address and a target address
    withAddress = withAddress.filter((f) => f.targetAddress); // remove the one that have not been resolved
    withAddress = withAddress.filter((f) => f.currentAddress); // remove the one that have not been resolved
    withAddress = withAddress.filter(
      (f) => f.currentAddress !== f.targetAddress,
    ); // remove the one that are the same, so no change needed

    // identify the selectors of the facets
    withAddress.forEach((f) => {
      // get the existing selectors
      const existing = this.facets.find(
        (facet) => facet.target === f.currentAddress,
      );
      if (existing) {
        // when not found we keep an empty array
        f.existingSelectors = existing.functions
          // remove the __init???(...) functions
          .filter(
            (func) => !initFunctions.includes(func.fullName!.split("(")[0]),
          );
      }
      // get the new selectors if the facet is a name
      if (this.hasContract(f.withFacet)) {
        f.newSelectors = this.internalCombined.contractSelectors
          .get(f.withFacet)!
          .map((selector) => ({
            selector,
            fullName:
              this.internalCombined.functions.get(selector) ||
              `NoName_${selector}()`,
          }))
          // remove the __init???(...) functions
          .filter(
            (func) => !initFunctions.includes(func.fullName?.split("(")[0]),
          );
      } else {
        // the withFacet is the zero address, we do not have the selectors
        f.newSelectors = [];
      }
    });

    // now we have the existing selectors and the new selectors for each facet
    // we can now identify the selectors that need to be added, replaced and removed
    const mapDiamondCuts: Map<string, DiamondCut> = new Map(); // key is target-action
    for (const f of withAddress) {
      // identify the selectors to remove
      const toRemove = f.existingSelectors.filter(
        (s) => !f.newSelectors.find((ns) => ns.selector === s.selector),
      );
      // identify the selectors to add
      const toAdd = f.newSelectors.filter(
        (ns) => !f.existingSelectors.find((s) => s.selector === ns.selector),
      );
      // identify the selectors to replace
      const toReplace = f.newSelectors.filter((ns) =>
        f.existingSelectors.find((s) => s.selector === ns.selector),
      );
      // build the diamond cut
      toRemove.forEach((s) => {
        const key = `${f.currentAddress}-${FacetCutAction.Remove}`;
        if (!mapDiamondCuts.has(key)) {
          mapDiamondCuts.set(key, {
            target: ZeroAddress,
            action: FacetCutAction.Remove,
            selectors: [],
          });
        }
        mapDiamondCuts.get(key)!.selectors.push(s.selector);
      });
      toAdd.forEach((s) => {
        const key = `${f.targetAddress}-${FacetCutAction.Add}`;
        if (!mapDiamondCuts.has(key)) {
          mapDiamondCuts.set(key, {
            target: f.targetAddress,
            action: FacetCutAction.Add,
            selectors: [],
          });
        }
        mapDiamondCuts.get(key)!.selectors.push(s.selector);
      });
      toReplace.forEach((s) => {
        const key = `${f.targetAddress}-${FacetCutAction.Replace}`;
        if (!mapDiamondCuts.has(key)) {
          mapDiamondCuts.set(key, {
            target: f.targetAddress,
            action: FacetCutAction.Replace,
            selectors: [],
          });
        }
        mapDiamondCuts.get(key)!.selectors.push(s.selector);
      });
    }

    // now we have the diamond cuts, we can now execute
    const diamondCuts = Array.from(mapDiamondCuts.values());
    // console.log("Diamond Cuts", diamondCuts);
    if (diamondCuts.length > 0) {
      await this.executioner.executer(
        this.config.writableName,
        this.getContract(this.config.writableName),
        this._deployedAt.rootAddress,
        "diamondCut",
        diamondCuts,
        ZERO_ADDRESS,
        "0x",
      );
    }

    // now we need to call the __init???(...) function on the new facets
    const initPromises = withAddress.map(async (f) => {
      const executedFunc: string[] = [];
      // try all 3 type of init functions
      for (const { action, address } of [
        { action: FacetCutAction.Remove, address: f.currentAddress },
        { action: FacetCutAction.Replace, address: f.targetAddress },
        { action: FacetCutAction.Add, address: f.targetAddress },
      ]) {
        const key = `${address}-${action}`;
        // did we have a cut for this action ?
        if (mapDiamondCuts.has(key)) {
          let funcName = initFunctions[action];
          let funcAbi = this.getContractFunction(f.withFacet, funcName);
          if (!funcAbi) {
            // try the generic __init(...) function
            funcName = initFunctions[FacetCutAction.All];
            funcAbi = this.getContractFunction(f.withFacet, funcName);
          }
          // if we found a function to execute and it is not already executed
          if (funcAbi && !executedFunc.includes(funcAbi.name!)) {
            await this.executioner.executer(
              this.config.writableName,
              this.getContract(this.config.writableName),
              this._deployedAt!.rootAddress,
              "diamondCut",
              [], // No cut to perform, we just use the init data
              address,
              AbiCoder.encodeFunctionCall(funcAbi, f.initParams || []),
            );
            executedFunc.push(funcAbi.name!);
          }
        }
      }
    });
    await Promise.all(initPromises);

    await this.loadFacets();
    return this._deployedAt;
  }
}
