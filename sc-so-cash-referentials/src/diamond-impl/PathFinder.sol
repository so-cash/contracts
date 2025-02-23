// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {
  ISoCashPathFinder, 
  ISoCashCountryManager, 
  BankIdentifier} from "../intf/so-cash-referential.sol";
import {PathFinderInternal} from "./PathFinderInternal.sol";

contract PathFinder is PathFinderInternal, ISoCashPathFinder{
  function resolveRoute(bytes3 currency, BankIdentifier memory from, BankIdentifier memory target) external view override returns (bool resolved, BankIdentifier[] memory route) {
    // ATTENTION: we need the country manager reference to resolve the routes and this is another facet of the diamond
    // So here we assume that the global referential will implement the ISoCashCountryManager interface
    ISoCashCountryManager countryManager = ISoCashCountryManager(address(this));
    (resolved, route, ) = this.resolveRoute2(countryManager, currency, from, target);
  }
}