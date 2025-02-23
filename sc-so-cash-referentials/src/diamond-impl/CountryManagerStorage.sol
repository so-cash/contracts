
// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {ISoCashCountryReferential} from "../intf/so-cash-referential.sol";

library CountryManagerStorage {
  // Layout struct holds the state variables for the Diamond facet.
  struct Layout {
    mapping(bytes2 => ISoCashCountryReferential) countries;
  }

  // Unique storage slot for CountryManagerStorage.
  bytes32 internal constant STORAGE_SLOT = keccak256("so-cash.ref.country-manager.storage");

  // Returns the storage layout for the CountryManager facet.
  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }
}