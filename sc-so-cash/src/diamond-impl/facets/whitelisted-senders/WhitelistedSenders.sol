// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;


import {WhitelistedSendersInternal} from "./WhitelistedSendersInternal.sol";
import {IWhitelistedSenders} from "../../../intf/whitelisted-senders.sol";


contract WhitelistedSenders is WhitelistedSendersInternal, IWhitelistedSenders {
    function isWhitelisted(address a) external view override returns (bool) {
        return _isWhitelisted(a);
    }

    function whitelist(address newSender) external onlyWhitelisted override {
        _whitelist(newSender);
    }

    function blacklist(address oldSender) external onlyWhitelisted override {
        _blacklist(oldSender);
    }
}