// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {
  ISoCashGlobalReferential, 
  BankIdentifier
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {
  ISoCashBank,
  ISoCashAccount,
  AccountNumber,
  AccountData,
  TransferId,
  TransferInfo,
  RecipentInfo,
  TransferStatus,
  OperationDirection,
  ActionType,
  SO_CASH_BANK
  } from "../../../intf/so-cash-types.sol";
import {
  ISoCashInterBank,
  ISoCashBankTransferManagementInternal
} from "../../../intf/so-cash-bank.sol";
import {BankTransferManagementStorage} from "./BankTransferManagementStorage.sol";
import {BankBalanceManagementInternal} from "../bank-balances-mgmt/BankBalanceManagementInternal.sol";
import {LocalIBANCalculator} from "../iban/IBANService.sol";
import {SharedFunctions} from "../../libs/SharedFunctions.sol";

contract BankTransferManagementInternal is ISoCashBankTransferManagementInternal, BankBalanceManagementInternal {
  function _transferInfo(TransferId id) internal view returns (TransferInfo memory) {
    BankTransferManagementStorage .Layout storage l = BankTransferManagementStorage.layout();
    return l._transferDetails[id];
  } 

  function _createTransferInfo(ISoCashAccount from, RecipentInfo memory to, uint256 amount, string memory details) internal returns (TransferId) {
    BankTransferManagementStorage .Layout storage l = BankTransferManagementStorage.layout();
    TransferId id = TransferId.wrap(l._transferIdCounter++);
    l._transferDetails[id] = TransferInfo(from, to, block.timestamp, amount, TransferStatus.NEW, details, "");
    return id;
  }

  function _copyTransferInfo(TransferInfo memory ti) internal returns (TransferId) {
    // a copy of the transfer info is in NEW status on the receiving bank
    return _createTransferInfo(ti.sender, ti.recipient, ti.amount, ti.details);
  }

  function _setTransferStatus(TransferId id, TransferStatus status) internal {
    BankTransferManagementStorage .Layout storage l = BankTransferManagementStorage.layout();
    TransferInfo storage ti = l._transferDetails[id];
    if (ti.status == TransferStatus.PENDING && status == TransferStatus.STP) {
      ti.status = TransferStatus.PROCESSED;
    } else {
      ti.status = status;
    }
    if (ti.status >= TransferStatus.PENDING) {
      emit TransfertStateChanged(id, ti.status);
    }
  }

  function _adviceIfNeeded(ISoCashAccount account, uint256 amount, OperationDirection direction, TransferId id) internal returns (bool){
    if (SharedFunctions.notNullAccount(account)) {
      ISoCashInterBank cBank = ISoCashInterBank(SharedFunctions._ioa(account).getAttributeAddr(SO_CASH_BANK));
      if (SharedFunctions.notNullBank(ISoCashBank(address(cBank)))) {
        return cBank.advice(amount, direction, id);
      }
    }
    return false;
  }

  function _shouldPlaceInPending(
    ISoCashAccount from, ISoCashAccount to, TransferId id) internal returns (bool) {
    BankTransferManagementStorage .Layout storage l = BankTransferManagementStorage.layout();
    TransferInfo storage t = l._transferDetails[id];
    // using the status to determine if it is a new transaction or a pending that is retested
    if (t.status != TransferStatus.NEW) return false;
    bool result = false;
    if (SharedFunctions.notNullAccount(from)) {
      // disable funds movement on inactive accounts
      if (!_isActive(from)) {
        t.reason = string(abi.encodePacked(t.reason, result?", ":"", "Inactive sender account"));
        result = true;
      }
      
      // other conditions on sender here
    }
    if (SharedFunctions.notNullAccount(to)) {
      // disable funds movement on inactive accounts
      if (!_isActive(to)) {
        t.reason = string(abi.encodePacked(result?", ":"", "Inactive recipient account"));
        result = true;
      }      
      // other conditions on recipient here
    }
    return result;
  }  

  function _transferMintBurn(ActionType /* action */, ISoCashAccount sender, ISoCashAccount recipient, uint256 amount, TransferId id) internal returns (bool){
    if (_shouldPlaceInPending(sender, recipient, id)) {
      _setTransferStatus(id, TransferStatus.PENDING);
      return false;
    }
    _transferMintBurnBalances(sender, recipient, amount, id);
    _setTransferStatus(id, TransferStatus.STP);
    return true;
  }
}