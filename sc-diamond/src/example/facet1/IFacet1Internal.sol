// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

/**
  Interface to declare types and events needed in the internal implementation of Facet1.
  It is also meant to be inherited by IFacet1
 */
interface IFacet1Internal {
  struct Facet1Type {
    bool isFacet1; // just an example
  }
  event Facet1Event(uint256 indexed value, Facet1Type info);
}