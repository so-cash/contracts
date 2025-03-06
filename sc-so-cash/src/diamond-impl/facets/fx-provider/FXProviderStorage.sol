
// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import { ISoCashAccount, CCY } from "../../../intf/so-cash-types.sol";

library FXProviderStorage {
  // Layout struct holds the state variables for the Diamond facet.
  struct Layout {
    mapping (CCY => ISoCashAccount) _accounts;
    mapping (bytes32 => address) _rateUsedByOrigin; // Stores the tx.origin that used the rate for settlement for avoiding double using and auditing
    address _rateSignerAddress; // will be needed to verify the signature of the FX Rate
    string _fxRateSourceUrl;
  }

  // Unique storage slot for PathFinderStorage.
  bytes32 internal constant STORAGE_SLOT = keccak256("so-cash.bank.fxprovider.storage");

  // Returns the storage layout for the PathFinder facet.
  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }

  function __init(address rateSigner) internal {
    Layout storage l = layout();
    l._fxRateSourceUrl = "unset";
    l._rateSignerAddress = rateSigner;
  }
}