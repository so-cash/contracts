// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

import {IFacet2Internal} from "./IFacet2Internal.sol";
import {Facet2Storage} from "./Facet2Storage.sol";

/**
  This internal contract is intended to implement function that access the storage and are not meant to be exposed to the outside world.
  It is a choice to not use the storage layout directly in the Facet contract but it can be done 
 */

contract Facet2Internal is IFacet2Internal {
  function _setText(string memory value) internal {
    Facet2Storage.Layout storage l = Facet2Storage.layout();
    l.text = value;
    emit Facet2Event(Facet2Type(1));
  }

  function _getText() internal view returns (string memory) {
    return Facet2Storage.layout().text;
  }

  function _setValue(int v) internal {
    Facet2Storage.layout().value = v;
  }

  function _getValue() internal view returns (int) {
    return Facet2Storage.layout().value;
  }
}