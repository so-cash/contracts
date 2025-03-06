// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

import {OnlyOnceStorage} from "./OnlyOnceStorage.sol";

/**
  This internal contract is intended to implement function that access the storage and are not meant to be exposed to the outside world.
  It is a choice to not use the storage layout directly in the Facet contract but it can be done 
 */

contract OnlyOnceInternal {
  modifier onlyOnceSilent(bytes32 key) {
    if ( OnlyOnceStorage.onlyOnce(key) ) {
      _;
    }
  }
  modifier onlyOnce(bytes32 key) {
    require(OnlyOnceStorage.onlyOnce(key), "OnlyOnce: duplicate call");
    _;
  }
}