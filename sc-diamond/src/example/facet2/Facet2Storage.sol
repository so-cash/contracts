// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;


/**
  Library that is meant to be used by the Facet internal implementation to manage the storage data structure.
  The layout() function is meant to be internal so the library is embeded in the Facet contract.
 */

library Facet2Storage {
    struct Layout {
      string text;
      int256 value;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("sample.contracts.storage.Facet2");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function __init(string memory text) internal {
        Layout storage l = layout();
        l.text = text;
    }
}
