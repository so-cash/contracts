// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

/**
  Library that is meant to be used by the Facet internal implementation to manage the storage data structure.
  The layout() function is meant to be internal so the library is embeded in the Facet contract.
 */

library Facet1Storage {
    struct Layout {
      uint256 value;
      mapping(uint256 => address) addresses;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("sample.contracts.storage.Facet1");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function __init(uint256 value) internal {
        Layout storage l = layout();
        l.value = value;
    }
}
