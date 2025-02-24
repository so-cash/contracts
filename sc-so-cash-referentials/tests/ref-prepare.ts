import Web3 from "web3";

import refCombined from "../build/combined.json" assert { type: "json" };
import refContracts from "../build";
import {
  map,
  traceEventLog,
  contractsNames,
  createAccount,
  getNewWallet,
  checkContractCompilation,
  executioner,
} from "@so-cash/sc-shared";

import {
  CombinedFile,
  Diamond,
  DiamondCreateConfig,
} from "@fever-tokens/diamond/ts-lib";

export async function prepareContracts(web3: Web3, subs: boolean = true) {
  // check all contracts are present
  checkContractCompilation(refContracts, contractsNames.ref);
  checkContractCompilation(refContracts, contractsNames.refdiamond);

  const rootContract = refContracts.get(contractsNames.refdiamond.root.intf);
  const countryContract = refContracts.get(
    contractsNames.refdiamond.country.intf,
  );

  const adminUser = await getNewWallet(web3, "admin", true);
  const adminFRUser = await getNewWallet(web3, "adminFR");
  const adminUSUser = await getNewWallet(web3, "adminUS");
  const bankBOUser = await getNewWallet(web3, "bankBO");

  // subscribe and display all events
  const RootSub = subs
    ? rootContract.allEvents(adminUser.sub(), {})
    : undefined;
  if (RootSub) RootSub.on("log", traceEventLog("ROOT"));
  const CountrySub = subs
    ? countryContract.allEvents(adminUser.sub(), {})
    : undefined;
  if (CountrySub) CountrySub.on("log", traceEventLog("COUNTRY"));

  // deploy the root referential
  // const root = await rootContract.deploy(adminUser.newi());
  const rootDiamond = new Diamond(
    {
      combinedJson: refCombined as CombinedFile,
      rootName: contractsNames.refdiamond.root.base,
      readableName: contractsNames.refdiamond.root.readable,
      writableName: contractsNames.refdiamond.root.writable,
      facetNames: [
        contractsNames.refdiamond.root.finder,
        contractsNames.refdiamond.root.countryManager,
      ],
      initializeFunctionName: "initialize",
      initializeFunctionArgs: [],
    },
    executioner(refContracts, adminUser),
  );
  const rootDeployed = await rootDiamond.deploy();
  const root = rootContract.at(rootDeployed.rootAddress);

  const countryConfig: DiamondCreateConfig = {
    combinedJson: refCombined as CombinedFile,
    rootName: contractsNames.refdiamond.country.base,
    readableName: contractsNames.refdiamond.country.readable,
    writableName: contractsNames.refdiamond.country.writable,
    facetNames: [
      contractsNames.oppenzeppelin.ownable,
      contractsNames.refdiamond.country.bankController,
      contractsNames.refdiamond.country.countryState,
    ],
    initializeFunctionName: "initialize",
    initializeFunctionArgs: [], // To be fixed by country
  };

  // deploy FR and US country referentials
  // const countryFR = await countryContract.deploy(
  //   adminFRUser.newi(),
  //   Buffer.from("FR"),
  // );
  let countryDiamond = new Diamond(
    { ...countryConfig, initializeFunctionArgs: [Buffer.from("FR")] },
    executioner(refContracts, adminFRUser),
  );
  const countryFRDeployed = await countryDiamond.deploy();
  const countryFR = countryContract.at(countryFRDeployed.rootAddress);
  map(countryFR.deployedAt, "CountryFR");
  // const countryUS = await countryContract.deploy(
  //   adminUSUser.newi(),
  //   Buffer.from("US"),
  // );

  countryDiamond = new Diamond(
    { ...countryConfig, initializeFunctionArgs: [Buffer.from("US")] },
    executioner(refContracts, adminUSUser),
  );
  const countryUSDeployed = await countryDiamond.deploy();
  const countryUS = countryContract.at(countryUSDeployed.rootAddress);
  map(countryUS.deployedAt, "CountryUS");

  // register the country referentials to the root
  await root.setCountry(adminUser.send(), countryFR.deployedAt);
  await root.setCountry(adminUser.send(), countryUS.deployedAt);

  return {
    rootContract,
    countryContract,
    adminUser,
    adminFRUser,
    adminUSUser,
    bankBOUser,
    root,
    countryFR,
    countryUS,
    RootSub,
    CountrySub,
  };
}
