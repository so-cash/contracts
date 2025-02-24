// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {OwnableInternal} from "@fever-tokens/diamond/src/ownable/OwnableInternal.sol";
import {IERC20Metadata} from "@fever-tokens/diamond/src/token/ERC20/extensions/IERC20Metadata.sol";

import {
  ACCOUNT_NAME,
  ISoCashBank} from "../../../intf/so-cash-types.sol";

import {ISoCashBankExternal} from "../../../intf/so-cash-bank.sol";

import {AccountDataStorage} from "./AccountDataStorage.sol";


contract AccountDataInternal is OwnableInternal {
  /** Implement IERC20Metadata */
  function _name() internal view returns (string memory) {
    return string(AccountDataStorage.layout()._attributesStr[ACCOUNT_NAME]);
  }
  function _symbol() internal view returns (string memory) {
    return IERC20Metadata(_owner()).symbol();
  }
  function _decimals() internal view returns (uint8) {
    return IERC20Metadata(_owner()).decimals();
  }
  /** Implement so|cash Data */
  function _bank() internal view returns (ISoCashBankExternal) {
    return ISoCashBankExternal(_owner());
  }

  function _getAttributeStr(bytes32 key) internal view returns (string memory) {
    return string(AccountDataStorage.layout()._attributesStr[key]);
  }
  function _getAttributeNum(bytes32 key) internal view returns (int) {
    bytes32 v = AccountDataStorage.layout()._attributesNum[key];
    unchecked {
      return int(uint256(v));
    }
  }
  function _getAttributeAddr(bytes32 key) internal view returns (address) {
    return AccountDataStorage.layout()._attributesAddr[key];
  }

  function _setAttributeStr(bytes32 key, string memory value) internal {
    AccountDataStorage.layout()._attributesStr[key] = bytes(value);
  }
  function _setAttributeNum(bytes32 key, int value) internal {
    AccountDataStorage.layout()._attributesNum[key] = bytes32(uint256(value));
  }
  function _setAttributeAddr(bytes32 key, address value) internal {
    AccountDataStorage.layout()._attributesAddr[key] = value;
  }

}