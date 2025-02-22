// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

import {IFacet1Internal} from "./IFacet1Internal.sol";

/**
  Interface to declare types and events needed in the internal implementation of Facet1.
  It is also meant to be inherited by IFacet1
 */
interface IFacet1 is IFacet1Internal {
  function setValue(uint256 value) external;
  function getValue() external view returns (uint256);
  function setAddress(uint256 index, address account) external;
  function getAddress(uint256 index) external view returns (address);
}