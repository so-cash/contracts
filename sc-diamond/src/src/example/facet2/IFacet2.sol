// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

import {IFacet2Internal} from "./IFacet2Internal.sol";

/**
  Interface to declare types and events needed in the internal implementation of Facet2.
  It is also meant to be inherited by IFacet2
 */
interface IFacet2 is IFacet2Internal {
  function inc() external;
  function getVal() external view returns (int);
  function setText(string calldata text) external;
  function getText() external view returns (string memory);
}