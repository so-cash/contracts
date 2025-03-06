// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;


/**
  Library that is meant to be used by the Facet internal implementation to manage the storage data structure.
  The layout() function is meant to be internal so the library is embeded in the Facet contract.
 */

library OnlyOnceStorage {
    struct Layout {
      mapping(bytes32 => bool) _onlyOnceMap;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("fevertokens.contracts.storage.OnlyOnce");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
    
    function onlyOnce(bytes32 key) internal returns (bool) {
        Layout storage l = layout();
        if (l._onlyOnceMap[key]) {
            return false;
        }
        l._onlyOnceMap[key] = true;
        return true;
    }
}
