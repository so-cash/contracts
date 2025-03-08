// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

import { IERC173 } from "./IERC173.sol";
import { IOwnable } from "./IOwnable.sol";
// import { OwnableStorage } from "./OwnableStorage.sol";
import { OwnableInternal } from "./OwnableInternal.sol";

contract Ownable is IOwnable, OwnableInternal {
    /// @inheritdoc IERC173
    function owner() public view virtual returns (address) {
        return _owner();
    }

    /// @inheritdoc IERC173
    function transferOwnership(address account) public virtual onlyOwner {
        _transferOwnership(account);
    }

    /// @inheritdoc IOwnable
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    // need to be public to be called from the diamond and not external to be overriden and called by the inhering contract
    function __init() external onlyOnceSilent(_slot()) {
        _setOwner(msg.sender);
    }
}
