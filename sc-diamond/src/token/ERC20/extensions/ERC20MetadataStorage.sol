// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

library ERC20MetadataStorage {
    struct Layout {
        string name;
        string symbol;
        uint8 decimals;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("fevertokens.contracts.storage.ERC20Metadata");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function __init(
        string memory name,
        string memory symbol,
        uint8 decimals) internal {
        Layout storage l = layout();
        l.name = name;
        l.symbol = symbol;
        l.decimals = decimals;
    }  
}
