// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {ISoCashCountryReferential, ISoCashCountryManager} from "../intf/so-cash-referential.sol";
import {CountryManagerInternal} from "./CountryManagerInternal.sol";

contract CountryManager is CountryManagerInternal, ISoCashCountryManager{

  function setCountry(ISoCashCountryReferential countryContract) external {
    _setCountry(countryContract);
  }

  function getCountry(bytes2 country) external view returns (ISoCashCountryReferential) {
    return _getCountry(country);
  }
}