// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;
// we use the IERC20Metadata Interface but not the storage or internals as the name is in the attributes, the symbol and decimas are in the bank
import {IERC20Metadata} from "@fever-tokens/diamond/src/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20MetadataInternal} from "@fever-tokens/diamond/src/token/ERC20/extensions/ERC20MetadataInternal.sol";
import {
  AccountNumber,
  ISoCashAccount,
  ISoCashBank} from "../../../intf/so-cash-types.sol";
import {ISoCashAccountData} from "../../../intf/so-cash-account.sol";
import {AccountDataInternal} from "./AccountDataInternal.sol";

contract AccountData is IERC20Metadata, AccountDataInternal, ISoCashAccountData {
  /** Implement IERC20Metadata */
  function name() external view override returns (string memory) {
    return _name();
  }
  function symbol() external view override  returns (string memory) {
    return _symbol();
  }
  function decimals() external view override  returns (uint8) {
    return _decimals();
  }
  /** Implement so|cash Data */

  function getAttributeStr(bytes32 key) external view override returns (string memory) {
    return _getAttributeStr(key);
  }

  function getAttributeNum(bytes32 key) external view override returns (int) {
    return _getAttributeNum(key);
  }

  function getAttributeAddr(bytes32 key) external view override returns (address) {
    return _getAttributeAddr(key);
  }

  function setAttributeStr(bytes32 key, string memory value) external override {
    _setAttributeStr(key, value);
  }

  function setAttributeNum(bytes32 key, int value) external override {
    _setAttributeNum(key, value);
  }

  function setAttributeAddr(bytes32 key, address value) external override {
    _setAttributeAddr(key, value);
  }

  function bank() external view override returns (ISoCashBank) {
    return ISoCashBank(address(_bank()));
  }

  function iban() external view override returns (string memory) {
    return _bank().ibanOf(ISoCashAccount(address(this)));
  }

  function accountNumber() external view override returns (AccountNumber) {
    return _bank().accountNumberOf(ISoCashAccount(address(this)));
  }
}