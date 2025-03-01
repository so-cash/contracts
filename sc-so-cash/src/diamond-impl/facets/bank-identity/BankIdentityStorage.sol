
// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {AddressUtils} from "@fever-tokens/diamond/src/utils/AddressUtils.sol";
import {
  ISoCashGlobalReferential, 
  BankIdentifier
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {BIC} from "../../../intf/so-cash-types.sol";

library BankIdentityStorage {
  // Layout struct holds the state variables for the Diamond facet.
  struct Layout {
    ISoCashGlobalReferential referential;
    BIC bic;
    BankIdentifier bankIdentifier;
    string version; // version of the code (attention, we cannot yet address the multiple version config of facets)
    uint256 _deployedAtBlock; // used to complement the version number in order to cross check the time of existance with the version number for debugging
  }

  // Unique storage slot for PathFinderStorage.
  bytes32 internal constant STORAGE_SLOT = keccak256("so-cash.bank.identity.storage");

  // Returns the storage layout for the PathFinder facet.
  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }

  function __init(ISoCashGlobalReferential referential, BIC bic, BankIdentifier memory id) internal {
    Layout storage l = layout();
    l.referential = referential;
    require(AddressUtils.isContract(address(referential)), "SoC: Invalid referential address - not a contract");
    l.bic = bic;
    l.bankIdentifier = id;
    l.version = "2.1.0";
    l._deployedAtBlock = block.number;
  }
}