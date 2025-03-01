
// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {CountryCode} from "./I_IBANService.sol";

library IBANBaseStorage {
  // Layout struct holds the state variables for the Diamond facet.
  struct Layout {
    mapping(CountryCode => address) _facets;
  }

  // Unique storage slot for PathFinderStorage.
  bytes32 internal constant STORAGE_SLOT = keccak256("so-cash.iban-service.storage");

  // Returns the storage layout for the PathFinder facet.
  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }

}