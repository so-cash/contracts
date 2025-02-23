
// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {ISoCashBankExternal} from "@so-cash/sc-so-cash/src/intf/so-cash-bank.sol";
import {CodeType, BankIdentifier, BankAccount} from "../intf/so-cash-referential.sol";

library CountryStateStorage {
  // Layout struct holds the state variables for the Diamond facet.
  struct Layout {
    bytes2 countryCode;
    // index(codes) => currency => bank module
    mapping(bytes32 => mapping(bytes3 => ISoCashBankExternal)) bankModules;
    // index(codes) => currency => bank identifier
    mapping(bytes32 => BankIdentifier) bankIds;
    // index(codes) => currency => correspondent bank index
    mapping(bytes32 => mapping(bytes3 => bytes32[])) correspondentBanks;
    // index(codes) => currency => SSI (for the moment only one SSI per bank/currency)
    mapping(bytes32 => mapping(bytes3 => BankAccount)) SSIs;
  }

  // Unique storage slot for PathFinderStorage.
  bytes32 internal constant STORAGE_SLOT = keccak256("so-cash.ref.country-state.storage");

  // Returns the storage layout for the PathFinder facet.
  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }

  function __init(bytes2 countryCode) internal {
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    l.countryCode = countryCode;
  }
}