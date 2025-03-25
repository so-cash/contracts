import Web3 from "web3";

import refContracts from "../build";
import {
  map,
  traceEventLog,
  contractsNames,
  getNewWallet,
  checkContractCompilation,
  createRootReferential,
  createCountryReferential,
} from "@so-cash/sc-shared";

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

  const root = await createRootReferential(refContracts, adminUser);

  // deploy FR and US country referentials
  const countryFR = await createCountryReferential(
    refContracts,
    adminFRUser,
    "FR",
  );
  map(countryFR.deployedAt, "CountryFR");
  const countryUS = await createCountryReferential(
    refContracts,
    adminUSUser,
    "US",
  );
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
