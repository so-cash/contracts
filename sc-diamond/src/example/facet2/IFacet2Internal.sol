// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

/**
  Interface to declare types and events needed in the internal implementation of Facet2.
  It is also meant to be inherited by IFacet2
 */
interface IFacet2Internal {
  struct Facet2Type {
    int value; // just an example
  }
  event Facet2Event(Facet2Type info);
}