
// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

// import {
//   ISoCashGlobalReferential, 
//   BankIdentifier
//   } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {
  ISoCashAccount,
  AccountData,
  AccountNumber,
  TransferId,
  TransferInfo,
  BIC} from "../../../intf/so-cash-types.sol";

library BankTransferManagementStorage {
  // Layout struct holds the state variables for the Diamond facet.
  struct Layout {
    uint256 _transferIdCounter;
    mapping(TransferId => TransferInfo) _transferDetails;

  }

  // Unique storage slot for PathFinderStorage.
  bytes32 internal constant STORAGE_SLOT = keccak256("so-cash.bank.transfers.storage");

  // Returns the storage layout for the PathFinder facet.
  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }

  function __init() internal {
    Layout storage l = layout();
    l._transferIdCounter = 1;
  }
}