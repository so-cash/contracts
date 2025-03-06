// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {IERC20Base} from "@fever-tokens/diamond/src/token/ERC20/base/IERC20Base.sol";
import {ERC20MetadataInternal} from "@fever-tokens/diamond/src/token/ERC20/extensions/ERC20MetadataInternal.sol";

import {
  ISoCashGlobalReferential, 
  BankIdentifier,
  CodeType
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {
  ISoCashBank,
  ISoCashAccount,
  RecipentInfo,
  AccountNumber,
  TransferId,
  TransferInfo,
  BIC} from "../../../intf/so-cash-types.sol";
import {ISoCashBankExternalWOTransfer} from "../../../intf/so-cash-bank.sol";
import {BankERC20MetadataInternal} from "../bank-erc20/BankERC20MetadataInternal.sol";
import {BankIdentityInternal} from "../bank-identity/BankIdentityInternal.sol";
import {BankBalanceManagementInternal} from "../bank-balances-mgmt/BankBalanceManagementInternal.sol";
import {BankTransferManagementInternal} from "../bank-transfers-mgmt/BankTransferManagementInternal.sol";
import {BankCorrespondentInternal} from "../bank-correspondents/BankCorrespondentInternal.sol";

contract BankExternalServices is ISoCashBankExternalWOTransfer, BankERC20MetadataInternal, BankIdentityInternal, BankBalanceManagementInternal, BankTransferManagementInternal, BankCorrespondentInternal {
  /* IERC20Base Implementation */
  function totalSupply() external view override returns (uint256) {
    return _totalSupply();
  }
  function symbol() external view override returns (string memory) {
    return string(abi.encodePacked(_ccy()));
  }

  function name() external view override returns (string memory) {
    return _name();
  }

  function decimals() external view override returns (uint8) {
    return _decimals();
  }

  function balanceOf(address account) external view override returns (uint256) {
    return _balanceOf(account);
  }

  // function transfer(address recipient, uint256 amount) external override returns (bool) {
  function transfer(address , uint256 ) external pure returns (bool) {
    revert("Not implemented");
  }

  // function allowance(address owner, address spender) external view override returns (uint256) {
  function allowance(address , address ) external pure returns (uint256) {
    revert("Not implemented");
  }

  // function approve(address spender, uint256 amount) external override returns (bool) {
  function approve(address , uint256 ) external pure returns (bool) {
    revert("Not implemented");
  }

  // function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
  function transferFrom(address , address , uint256 ) external pure returns (bool) {
    revert("Not implemented");
  }

  // function increaseAllowance(address spender, uint256 addedValue) external override returns (bool) {
  function increaseAllowance(address , uint256 ) external pure returns (bool) {
    revert("Not implemented");
  }

  // function decreaseAllowance(address spender, uint256 subtractedValue) external override returns (bool) {
  function decreaseAllowance(address , uint256 ) external pure returns (bool) {
    revert("Not implemented");
  }

  /* Rest of the implementation */
  function bic() external view override returns (string memory) {
    return string(abi.encodePacked(_bic()));
  }

  function codes() external view override returns (CodeType bankCode, CodeType branchCode) {
    BankIdentifier memory id = _bankIdentifier();
    return (id.codes[0], id.codes[1]);
  }

  function bankIdentifier() external view override returns (BankIdentifier memory) {
    return _bankIdentifier();
  }

  function country() external view returns (bytes2 ) {
    return _country();
  }
  function version() external view override returns (string memory) {
    return _version();
  }
  function lockedBalanceOf(ISoCashAccount account) external view override returns (uint256) {
    return _lockedBalanceOf(account);
  }
  function unlockedBalanceOf(ISoCashAccount account) external view override returns (uint256) {
    return _unlockedBalanceOf(account);
  }
  function fullBalanceOf(ISoCashAccount account) external view override returns (int256) {
    return _fullBalanceOf(account);
  }
  function accountNumberOf(ISoCashAccount account) external view override returns (AccountNumber) {
    return _accountNumberOf(account);
  }
  function addressOf(AccountNumber accountNumber) external view override returns (ISoCashAccount) {
    return _addressOf(accountNumber);
  }
  function addressOfFullAccount(string memory account) external view override returns (ISoCashAccount) {
    return _addressOfFullAccount(account);
  }

  function transferInfo(TransferId id) external view override returns (TransferInfo memory) {
    return _transferInfo(id);
  }
  function lockFunds(uint amount) external onlyRegisteredAccount override returns (bool){
    return _lock(ISoCashAccount(msg.sender), amount);
  }
  function unlockFunds(uint amount) external onlyRegisteredAccount override returns (bool){
    return _unlock(ISoCashAccount(msg.sender), amount);
  }

  function ibanOf(ISoCashAccount account) external view override returns (string memory) {
    AccountNumber an = _accountNumberOf(account);
    return _encodeIbanOfAccount(an);
  }
  function decodeIBAN(string memory iban) external view override returns (ISoCashBank bank, ISoCashAccount account) {
    (bank, account, ) = _decodeIBANToSoCashContracts(iban);
  }
}