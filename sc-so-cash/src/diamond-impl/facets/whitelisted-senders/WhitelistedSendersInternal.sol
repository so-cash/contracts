// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {OwnableInternal} from "@fever-tokens/diamond/src/ownable/OwnableInternal.sol";
import {WhitelistedSendersStorage} from "./WhitelistedSendersStorage.sol";
import {IWhitelistedSendersInternal} from "../../../intf/whitelisted-senders.sol";
contract WhitelistedSendersInternal is OwnableInternal, IWhitelistedSendersInternal {

  modifier onlyWhitelisted() {
      require(
          _isWhitelisted(msg.sender),
          "WLS: Caller not allowed to perform the action"
      );
      _;
  }
    function _isWhitelisted(address a) internal view virtual returns (bool) {
        WhitelistedSendersStorage.Layout storage l = WhitelistedSendersStorage.layout();
        return a == _owner() || l._whitelistedSenders[a];
    }

    function _whitelist(address newSender) onlyWhitelisted() internal virtual onlyWhitelisted {
        WhitelistedSendersStorage.Layout storage l = WhitelistedSendersStorage.layout();
        l._whitelistedSenders[newSender] = true;
        emit Whitelisted(newSender, true);
    }

    function _blacklist(address oldSender) onlyWhitelisted() internal virtual onlyWhitelisted {
        WhitelistedSendersStorage.Layout storage l = WhitelistedSendersStorage.layout();
        l._whitelistedSenders[oldSender] = false;
        emit Whitelisted(oldSender, false);
    }

}