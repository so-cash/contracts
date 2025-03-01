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
  TransferStatus
} from "../../../intf/so-cash-types.sol";
import {
  ISoCashBankExternalTransfer,
  ISoCashInterBank,
  ISoCashBankExternal,
  ISoCashBackOfficePayments,
  ISoCashBank
  } from "../../../intf/so-cash-bank.sol";
import {
  BankPaymentInternal} from "./BankPaymentInternal.sol";
import {BankCorrespondentInternal} from "../bank-correspondents/BankCorrespondentInternal.sol";
import {BankBalanceManagementInternal} from "../bank-balances-mgmt/BankBalanceManagementInternal.sol";

contract BankExtPayment is ISoCashInterBank, ISoCashBankExternalTransfer, BankPaymentInternal {
  function transfer(RecipentInfo calldata to, uint256 amount, string calldata details) external override onlyRegisteredAccount returns (bool) {
    return _transfer(ISoCashAccount(msg.sender), to, amount, details);
  }

  function interbankTransfer(BankAccount calldata ssi, RecipentInfo calldata to, uint256 amount, TransferId id) external override onlyCorrespondentBank returns (bool) {
    return _interbankTransfer(ISoCashBankExternal(msg.sender), ssi, to, amount, id);
  }
  function interbankNetting(uint256 amount, TransferId id) external override onlyCorrespondentBank returns (bool) {
    return _interbankNetting(ISoCashBank(msg.sender), amount, id);
  }
  function advice(uint256 amount, OperationDirection direction, TransferId id) external override returns (bool) {
    return _advice(ISoCashBankExternal(msg.sender), amount, direction, id);
  }

}