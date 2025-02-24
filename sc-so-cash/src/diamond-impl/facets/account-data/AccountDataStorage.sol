
// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {ACCOUNT_NAME} from "../../../intf/so-cash-types.sol";

library AccountDataStorage {
  // Layout struct holds the state variables for the Diamond facet.
  struct Layout {
    mapping(bytes32 => bytes) _attributesStr;
    mapping(bytes32 => bytes32) _attributesNum;
    mapping(bytes32 => address) _attributesAddr;
  }

  // Unique storage slot for PathFinderStorage.
  bytes32 internal constant STORAGE_SLOT = keccak256("so-cash.account.data.storage");

  // Returns the storage layout for the PathFinder facet.
  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }

  function __init(string memory name) internal {
    Layout storage l = layout();
    l._attributesStr[ACCOUNT_NAME] = bytes(name);
  }
}