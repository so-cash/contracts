/**
 * @packageDocumentation
 * @module sc-diamond
 * This typescript library is used to facilitate the preparation of diamond deployment with its facets
 */
import AbiCoder from "web3-eth-abi";
import Utils, { AbiItem } from "web3-utils";
// fix the lib issue which type declares jsonInterfaceMethodToString but really it exports the function as _jsonInterfaceMethodToString
const jsonInterfaceMethodToString: typeof Utils.jsonInterfaceMethodToString = (
  Utils as any
)._jsonInterfaceMethodToString;

export interface CompiledSmartContract {
  abi: AbiItem[];
  bin: string;
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
interface InternalComibinedFile extends CombinedFile {
  names: Map<string, ContractInfos>; // contract or library name to full name (file:contract)
  selectorContractMapping: Map<string, string[]>; // selector to list of contract names that have this selector
  functions: Map<string, string>; // function signature to function name
  contractSelectors: Map<string, string[]>; // contract name to list of selectors
}

export enum FacetCutAction {
  Add,
  Replace,
  Remove,
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
function resolvePreference(fullName1: string, fullName2: string, duplicatePref: RegExp[]): string {
  for (const pref of duplicatePref) {
    if (pref.test(fullName1)) return fullName1;
    if (pref.test(fullName2)) return fullName2;
  }
  return fullName1;
}

/** Function to pre process the combined file so that getting the selectors, functions, contract are easier */
function prepareCombined(combined: CombinedFile, duplicatePref: RegExp[]=[]): InternalComibinedFile {
  const names = new Map<string, ContractInfos>();
  const selectorContractMapping = new Map<string, string[]>();
  const functions = new Map<string, string>();
  const contractSelectors = new Map<string, string[]>();
  for( const fullName of Object.keys(combined.contracts) as ContractFullName[]) {
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

export class Diamond {
  protected _deployedAt?: DeployedDiamond;
  protected _facets?: Facet[];
  protected internalCombined: InternalComibinedFile;
  constructor(
    private config: DiamondCreateConfig,
    private executioner: IExecutioner,
    duplicatePref: RegExp[]=[]
  ) {
    this.internalCombined = prepareCombined(config.combinedJson, duplicatePref);
  }

  protected async loadFacets(facets?: RawFacet[]) {
    if (!facets && this._deployedAt?.rootAddress) {
      // no facets provided, load from the deployed diamond
      facets = await await this.executioner.reader(
        "IDiamondReadable",
        this.getContract("IDiamondReadable"),
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
        fullName: this.internalCombined.functions.get(selector),
      })),
      name: this.findBestContractNameBySelectors(facet.selectors),
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
  }

  static async fromAddress(
    config: DiamondBaseConfig,
    rootAddress: string,
    exec: IExecutioner,
  ): Promise<Diamond> {
    const internalCombined = prepareCombined(config.combinedJson);
    // first collect the facet addresses
    const facets: RawFacet[] = await exec.reader(
      "IDiamondReadable",
      Diamond.getContractFromCombined(internalCombined, "IDiamondReadable"),
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
    combined: InternalComibinedFile,
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
      .map((abi) => AbiCoder.encodeFunctionSignature(abi));
  }

  protected findBestContractNameBySelectors(
    selectors: string[],
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
      // contracts with code have a bonus of one to get it before their interface
      if (this.internalCombined.names.get(name)?.hasCode) count++;
      counts.set(name, count);
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

  async deploy(debug?: boolean): Promise<DeployedDiamond> {
    // start by deploying the facets, readable and writable facets
    const facetAddresses: { [name: string]: string } = {};
    for (const name of [
      ...this.config.facetNames,
      this.config.readableName,
      this.config.writableName,
    ]) {
      const contract = this.getContract(name);
      // no parameters expected
      facetAddresses[name] = await this.executioner.deployer(name, contract, {
        isFacet: true,
      });
    }
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
      const [name, target] = Object.entries(facetAddresses).find(([_, v]) => v === cut.target)!;
      cut.selectors.forEach((selector) => {
        if (selectors.has(selector)) {
          selectors.get(selector)!.push(name);
          console.warn(
            `WARN: Selector ${selector}:${this.internalCombined.functions.get(selector)} is present in multiple facets [${selectors.get(selector)!.join(',')}], this may lead to unexpected behavior`,
          );
        } else {
          selectors.set(selector, [name]);
        }
      })
    });
    if (debug) {
      // display the the facets and selectors names
      this.config.facetNames.forEach((name, index) => {
        console.log(`Facet ${name} : ${this.internalCombined.names.get(name)?.fullName}`);
        diamondCut[index].selectors.forEach((selector) => {
          console.log(`  - ${this.internalCombined.functions.get(selector)} - ${selector}`);
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
    ...replace: { facet: string; withFacet: string }[]
  ): Promise<DeployedDiamond> {
    if (!this._deployedAt) {
      throw new Error("Diamond not yet deployed");
    }
    const rootAddress = this._deployedAt.rootAddress;
    const replaceTargets = replace.map(
      ({ facet }) => this._deployedAt!.facetAddresses[facet],
    );
    const newFacets = replace.map(({ withFacet }) => withFacet);
    const newFacetAddresses: { [name: string]: string } = {};
    const newFacetFunctions: FacetFunctionWithTarget[] = [];

    // start by deploying the new facets
    for (const name of newFacets) {
      const contract = this.getContract(name);
      // no parameters expected, deploy
      newFacetAddresses[name] = await this.executioner.deployer(
        name,
        contract,
        { isFacet: true, isUpgrade: true },
      );
      // get the list of selectors of the new facet
      newFacetFunctions.push(
        ...this.internalCombined.contractSelectors
          .get(name)!
          .map((selector) => ({
            selector,
            fullName: this.internalCombined.functions.get(selector),
            target: newFacetAddresses[name],
          })),
      );
    }

    // identify the gaps between the existing facets and the new ones
    // replace array is the list of existing facet address (facetAddress) and the name of the new facet class to replace it with (withFacet)

    // start by getting the list of selectors in the existing diamond's facets
    const existing = this.facets.filter((facet) =>
      replaceTargets.includes(facet.target),
    );
    const existingSelectors = existing.flatMap<FacetFunctionWithTarget>(
      (facet) => facet.functions.map((f) => ({ ...f, target: facet.target })),
    );

    let diamondCuts: DiamondCut[] = [];
    const touchedTargets = new Set<string>();
    // parse the new facet selectors to see if these functions already exist in the diamond
    for (const { selector, target } of newFacetFunctions) {
      const existingFunction = existingSelectors.find(
        (f) => f.selector === selector,
      );
      if (existingFunction) {
        // replace the existing function
        diamondCuts.push({
          target,
          action: FacetCutAction.Replace,
          selectors: [selector],
        });
        touchedTargets.add(existingFunction.target);
      } else {
        // add the new function
        diamondCuts.push({
          target,
          action: FacetCutAction.Add,
          selectors: [selector],
        });
      }
    }
    // we now need to identify if there are selector to remove, these are the ones that are in the old addresses but not replaced
    for (const { selector, target } of existingSelectors) {
      if (touchedTargets.has(target)) {
        // this selector is concerned
        // has it been replaced ?
        const replaced = diamondCuts.find((cut) =>
          cut.selectors.includes(selector),
        );
        if (!replaced) {
          // this selector is not replaced, remove it
          diamondCuts.push({
            target: ZERO_ADDRESS,
            action: FacetCutAction.Remove,
            selectors: [selector],
          });
        }
      }
    }
    // now reconstruct the cuts so that we reduce the number of cuts by grouping on targt and action
    const groupedCuts: Map<string, DiamondCut> = new Map(); // the key is target+action
    diamondCuts.forEach((cut) => {
      const key = `${cut.target}-${cut.action}`;
      if (groupedCuts.has(key)) {
        groupedCuts.get(key)!.selectors.push(...cut.selectors);
      } else {
        groupedCuts.set(key, { ...cut });
      }
    });
    diamondCuts = Array.from(groupedCuts.values());
    // console.log("Diamond Cuts", diamondCuts);

    let facetAddresses = { ...this._deployedAt.facetAddresses };
    for (const facet in facetAddresses) {
      if (replaceTargets.includes(facetAddresses[facet])) {
        delete facetAddresses[facet];
      }
    }
    facetAddresses = { ...facetAddresses, ...newFacetAddresses };

    await this.executioner.executer(
      this.config.writableName,
      this.getContract(this.config.writableName),
      rootAddress,
      "diamondCut",
      diamondCuts,
      ZERO_ADDRESS,
      "0x",
    );
    await this.loadFacets();
    this._deployedAt = {
      rootAddress,
      facetAddresses,
    };
    return this._deployedAt;
  }
}
