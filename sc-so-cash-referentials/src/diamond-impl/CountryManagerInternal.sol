// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {ISoCashCountryReferential, ISoCashCountryManagerInternal} from "../intf/so-cash-referential.sol";
import {CountryManagerStorage} from "./CountryManagerStorage.sol";

contract CountryManagerInternal is ISoCashCountryManagerInternal{

  function _setCountry(ISoCashCountryReferential countryContract) internal {
    CountryManagerStorage.Layout storage l = CountryManagerStorage.layout();
    bytes2 country = countryContract.countryCode();
    l.countries[country] = countryContract;
    emit CountrySet(country, countryContract);
  }

  function _getCountry(bytes2 country) internal view returns (ISoCashCountryReferential) {
    return CountryManagerStorage.layout().countries[country];
  }
}