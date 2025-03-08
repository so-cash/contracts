// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;
import {OnlyOnceStorage} from "../only-once/OnlyOnceStorage.sol";

library OwnableStorage {
    struct Layout {
        address owner;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("openzeppelin.contracts.storage.Ownable");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function __init(address _owner) internal {
        if (OnlyOnceStorage.onlyOnce(STORAGE_SLOT)) {
            OwnableStorage.Layout storage l = OwnableStorage.layout();
            l.owner = _owner;
        }
    }
}
