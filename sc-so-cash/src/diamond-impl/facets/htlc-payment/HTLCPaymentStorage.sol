
// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {HTLC} from "../../../intf/htlc-payment.sol";

library HTLCPaymentStorage {
  // Layout struct holds the state variables for the Diamond facet.
  struct Layout {
    uint256 _htlcCounter; // to generate unique ids for the HTLCs, starts at zero
    mapping(bytes32 => HTLC) _payments; // the HTLCs
  }

  // Unique storage slot for PathFinderStorage.
  bytes32 internal constant STORAGE_SLOT = keccak256("so-cash.htlc-payment.storage");

  // Returns the storage layout for the PathFinder facet.
  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }
}