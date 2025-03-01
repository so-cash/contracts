// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {
  IERC20
} from "@fever-tokens/diamond/src/token/ERC20/IERC20.sol";
import {
  ISoCashGlobalReferential, 
  BankIdentifier
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {
  ISoCashBank,
  ISoCashAccount,
  NostroAccount,
  BankModel,
  OperationDirection,
  TransferId,
  BankAccount
  } from "../../../intf/so-cash-types.sol";
import {
  ISoCashOwnedAccount
} from "../../../intf/so-cash-account.sol";
import {
  ISoCashInterBank,
  ISoCashBankExternal,
  ISoCashBankNostroManagementInternal
} from "../../../intf/so-cash-bank.sol";
import {BankNostroManagementStorage} from "./BankNostroManagementStorage.sol";
import {SharedFunctions} from "../../libs/SharedFunctions.sol";

contract BankNostroManagementInternal is ISoCashBankNostroManagementInternal {

  function _registerNostroAccount(BankAccount memory nostro) internal returns (bool) {
    require(nostro.model != BankModel.UNDEFINED, "SoC: Cannot register an undefined nostro model");
    require(address(nostro.bank) != address(0), "SoC: Cannot register a null bank nostro");
    require(address(nostro.account) != address(0), "SoC: Cannot register a null account nostro");
    if (nostro.model == BankModel.SO_CASH) {
      require(ISoCashOwnedAccount(nostro.account).bank() == ISoCashBank(nostro.bank), "SoC: Inconsistent bank and account");
    }
    int256 balance = _getNostroBalanceByModel(nostro.model, address(nostro.bank), address(nostro.account));
    BankNostroManagementStorage.Layout storage l = BankNostroManagementStorage.layout();
    l._nostros[nostro.bank] = NostroAccount(nostro.model, address(nostro.bank), address(nostro.account), balance, 0, 0);
    emit NostroAccountRegistration(nostro.model, nostro.bank, nostro.account, true);
    return true;
  }

  function _unregisterNostroAccount(address bank, address ) internal returns (bool) {
    BankNostroManagementStorage.Layout storage l = BankNostroManagementStorage.layout();
    NostroAccount storage nostro = l._nostros[bank];
    if (nostro.model == BankModel.UNDEFINED) return false;
    // Need to emit before because else the nostro.bank, nostro.account are zeroed after the delete
    emit NostroAccountRegistration(nostro.model, nostro.bank, nostro.account, false);
    delete l._nostros[bank];
    return true;
  }

  function _getNostro(address bank, address) internal view returns (NostroAccount storage) {
    BankNostroManagementStorage.Layout storage l = BankNostroManagementStorage.layout();
    NostroAccount storage nostro = l._nostros[bank];
    return nostro;
  }

  function _nostroAccountModel(address bank, address) internal view returns (BankModel) {
    BankNostroManagementStorage.Layout storage l = BankNostroManagementStorage.layout();
    return l._nostros[bank].model;
  }

  function _getNostroBalanceByModel(BankModel model, address bank, address account) internal view returns (int256) {
    if (bank == address(0)) return 0;
    if (model == BankModel.SO_CASH) {
      return ISoCashBankExternal(bank).fullBalanceOf(ISoCashAccount(account));
    } else if (model == BankModel.ERC20) {
      return int256(IERC20(bank).balanceOf(account));
    } else {
      return 0;
    }
  }
  function _getNostroBalance(address bank, address) internal view returns (int256 actual, int256 last) {
    BankNostroManagementStorage.Layout storage l = BankNostroManagementStorage.layout();
    NostroAccount storage nostro = l._nostros[bank];
    last = nostro.lastBalance;
    actual = _getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);
  }

  // Process the reception of a notification from another bank that the nostro has changed
  function _adviceNostro(
    address bank, uint256 amount, OperationDirection direction, TransferId ) internal returns (bool) {
    
    BankNostroManagementStorage.Layout storage l = BankNostroManagementStorage.layout();
    NostroAccount storage nostro = l._nostros[bank];
    
    if (nostro.model != BankModel.SO_CASH) return false; // no nostro , do nothing and return false
    int256 balance = _getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);

    if (direction == OperationDirection.CREDIT) {
      nostro.lastAdviceAmount = int256(amount);
      require(nostro.lastBalance + int256(amount) == balance, "SoC: Our nostro has not been credited according to advice");
    } else {
      nostro.lastAdviceAmount = -int256(amount);
      require(nostro.lastBalance == balance + int256(amount), "SoC: Our nostro has not been debited according to advice");
    }
    // Update the last balance 
    nostro.lastBalance = balance;
    // Block number is used to detect if the nostro has been modified in the same transaction
    // but the transaction hash is not available, so this is a workaround not perfect
    // We need to use the some other scheme independent from the caller
    nostro.lastBlock = block.number;
    return true;
  }

  function _checkNostroBalanceAdjusted(BankAccount memory ssi, int256 amount) internal returns (bool) {
    // check that the nostro at bank that was used by the calling bank is actually a nostro at our level
    BankNostroManagementStorage.Layout storage l = BankNostroManagementStorage.layout();
    NostroAccount storage nostro = l._nostros[ssi.bank];
    require(nostro.account == ssi.account && nostro.model == ssi.model, "SoC: The account provided is not a nostro account");
    
    // We have 2 scenario to cover. One where the nostro has been updated via an Advise call, and one where it was not
    if (nostro.lastBlock == block.number) { // Advice was called, the balance is already updated
      require(nostro.lastAdviceAmount == amount, "SoC: Our nostro has not been credited of the right amount");
    } else {
      // check that our nostro has been updated and update it locally
      int256 balance = _getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);
      require(nostro.lastBalance + amount == balance, "SoC: Our nostro not been updated according to the amount");
      nostro.lastBalance = balance;
      nostro.lastBlock = block.number;
      nostro.lastAdviceAmount = amount;
    }
    
    return true;
  }

  function _synchroNostro(address bank, address) internal returns (bool) {
    BankNostroManagementStorage.Layout storage l = BankNostroManagementStorage.layout();
    NostroAccount storage nostro = l._nostros[bank];
    require(nostro.model != BankModel.UNDEFINED, "SoC: No nostro registered for this bank");

    nostro.lastBalance = _getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);
    nostro.lastBlock = 0;
    nostro.lastAdviceAmount = 0;
    return true;
  }
}