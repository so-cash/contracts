// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {ERC20MetadataInternal} from "@fever-tokens/diamond/src/token/ERC20/extensions/ERC20MetadataInternal.sol";
import {ERC20MetadataStorage} from "@fever-tokens/diamond/src/token/ERC20/extensions/ERC20MetadataStorage.sol";

contract BankERC20MetadataInternal is ERC20MetadataInternal {
    // This is a Facet, it must be initialized with the BankERC20MetadataStorage lib 
}

library BankERC20MetadataStorage {
  function __init(string memory name, string memory symbol, uint8 decimals) internal {
    bytes memory symbolBytes = abi.encodePacked(symbol);
    require(symbolBytes.length == 3, "SoC: Symbol expected to be 3 chars ISO currency code");
    // force uppercase 
    for (uint256 i = 0; i < symbolBytes.length; i++) {
      if (uint8(symbolBytes[i]) >= 97 && uint8(symbolBytes[i]) <= 122) {
        symbolBytes[i] = bytes1(uint8(symbolBytes[i]) - 32);
      }
    }
    ERC20MetadataStorage.__init(name, symbol, decimals);
  }
}