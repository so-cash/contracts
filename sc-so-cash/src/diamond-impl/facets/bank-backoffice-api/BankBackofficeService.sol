// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {
  ISoCashGlobalReferential, 
  BankIdentifier,
  CodeType
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {
  RecipentInfo,
  BankAccount,
  TransferId,
  OperationDirection,
  ISoCashAccount,
  BankModel,
  TransferStatus,
  ActionType,
  ZERO_ACCOUNT, ZERO_BANK, BIC, IBAN
} from "../../../intf/so-cash-types.sol";
import {
  ISoCashBank,
  ISoCashBankBackOfficeServices
  } from "../../../intf/so-cash-bank.sol";

import {WhitelistedSendersInternal} from "../whitelisted-senders/WhitelistedSendersInternal.sol";
import {BankPaymentInternal} from "../bank-payments/BankPaymentInternal.sol";
import {SharedFunctions} from "../../libs/SharedFunctions.sol";

contract BankBackOfficeServices is ISoCashBankBackOfficeServices, BankPaymentInternal, WhitelistedSendersInternal {

    function isCorrespondentRegistered(ISoCashBank bank) external override view returns (bool) {
      return _isCorrespondentRegistered(bank);
    }

    // TODO: replace by a different function - to be deprecated
    function correspondent(ISoCashBank bank) external override view returns (BankIdentifier memory cb) {
      if (_isCorrespondentRegistered(bank)) {
        return SharedFunctions._ibe(bank).bankIdentifier();
      } else {
        return BankIdentifier(0x0000, new CodeType[](0));
      }
    }

    function registerAccount(ISoCashAccount account) external override onlyWhitelisted returns (bool) {
      return _registerAccount(account);
    }

    function unregisterAccount(ISoCashAccount account) external override onlyWhitelisted returns (bool) {
      return _unregisterAccount(account);
    }

    function isAccountRegistered(ISoCashAccount account) external override view returns (bool) {
      return _isRegistered(account);
    }

    function toggleAccountActive(ISoCashAccount account) external override onlyWhitelisted returns (bool) {
      return _toggleAccountActive(account);
    }

    function isAccountActive(ISoCashAccount account) external override view returns (bool) {
      return _isActive(account);
    }

    function registerNostroAccount(BankAccount calldata nostro) external override onlyWhitelisted returns (bool) {
      return _registerNostroAccount(nostro);
    }

    function unregisterNostroAccount(address bank, address account) external override onlyWhitelisted returns (bool) {
      return _unregisterNostroAccount(bank, account);
    }

    function nostroAccountModel(address bank, address account) external override view returns (BankModel) {
      return _nostroAccountModel(bank, account);
    }

    function getNostroBalance(address bank, address account) external override view returns (int256 actual, int256 last) {
      return _getNostroBalance(bank, account);
    }

    function credit(ISoCashAccount account, uint256 amount, string calldata details) external override onlyWhitelisted returns (bool) {
      TransferId id = _createTransferInfo(
        ZERO_ACCOUNT, 
        RecipentInfo(account, BIC.wrap(0), IBAN.wrap(0)), 
        amount, details);
      bool success = _transferMintBurn(ActionType.MINT, ZERO_ACCOUNT, account, amount, id);
      _adviceIfNeeded(account, amount, OperationDirection.CREDIT, id);
      return success;

    }

    function debit(ISoCashAccount account, uint256 amount, string calldata details) external override onlyWhitelisted returns (bool) {
      TransferId id = _createTransferInfo(
        account, 
        RecipentInfo(ZERO_ACCOUNT, BIC.wrap(0), IBAN.wrap(0)), 
        amount, details);
      bool success = _transferMintBurn(ActionType.BURN, account, ZERO_ACCOUNT, amount, id);
      _adviceIfNeeded(account, amount, OperationDirection.DEBIT, id);
      return success;
    }
  
    function lockFunds(ISoCashAccount account, uint256 amount) external override onlyWhitelisted returns (bool) {
      return _lock(account, amount);
    }

    function unlockFunds(ISoCashAccount account, uint256 amount) external override onlyWhitelisted returns (bool) {
      return _unlock(account, amount);
    }
}