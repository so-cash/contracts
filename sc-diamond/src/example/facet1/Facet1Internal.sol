// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

import {IFacet1Internal} from "./IFacet1Internal.sol";
import {Facet1Storage} from "./Facet1Storage.sol";

/**
  This internal contract is intended to implement function that access the storage and are not meant to be exposed to the outside world.
  It is a choice to not use the storage layout directly in the Facet contract but it can be done 
 */

contract Facet1Internal is IFacet1Internal {
  using Facet1Storage for IFacet1Internal;
  function _setValue(uint256 value) internal {
    Facet1Storage.Layout storage l = Facet1Storage.layout(); 
    l.value = value;
    emit Facet1Event(value, Facet1Type(true));
  }

  function _getValue() internal view returns (uint256) {
    return Facet1Storage.layout().value;
  }

  function _setAddress(uint256 index, address account) internal {
    Facet1Storage.layout().addresses[index] = account;
  }

  function _getAddress(uint256 index) internal view returns (address) {
    return Facet1Storage.layout().addresses[index];
  }
}