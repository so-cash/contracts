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
  TransferStatus,
  ExecutionPlan,
  ZERO_ACCOUNT
} from "../../../intf/so-cash-types.sol";
import {
  ISoCashBankPaymentSimulation,
  ISoCashBankExternal,
  ISoCashBank
  } from "../../../intf/so-cash-bank.sol";
import {
  BankPaymentInternal} from "./BankPaymentInternal.sol";
import {BankCorrespondentInternal} from "../bank-correspondents/BankCorrespondentInternal.sol";
import {BankBalanceManagementInternal} from "../bank-balances-mgmt/BankBalanceManagementInternal.sol";

contract BankPaymentSimulation is ISoCashBankPaymentSimulation, BankPaymentInternal {
  
  function simulateTransfer(ISoCashAccount fromAccount, RecipentInfo memory to, uint256 amount) public view override returns (ExecutionPlan memory) {
    TransferId id = TransferId.wrap(0);
    return _transferExecutionPlan(fromAccount, to, amount, id);
  }
  function simulateInterbankTransfer(ISoCashBank fromBank, RecipentInfo memory to, uint256 amount) public view override returns (ExecutionPlan memory plan) {
    TransferId id = TransferId.wrap(0);
    plan = _interbankExecutionPlan(fromBank, to, amount, id);
    plan.debitLocalAccount = ZERO_ACCOUNT;
    return plan;
  }
}