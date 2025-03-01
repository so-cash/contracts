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
import {WhitelistedSendersInternal} from "../whitelisted-senders/WhitelistedSendersInternal.sol";

contract BankBOPayment is ISoCashBackOfficePayments, BankPaymentInternal, WhitelistedSendersInternal {

  function transferFrom(ISoCashAccount from, RecipentInfo calldata to, uint256 amount, string calldata details) external override onlyWhitelisted returns (bool) {
    return _transfer(from, to, amount, details);
  }

  function requestNetting(ISoCashBank _correspondent, ISoCashAccount loro, uint256 amount) external override onlyWhitelisted returns (bool) {
    return _requestNetting(_correspondent, loro, amount);
  }

  function synchroNostro(address bank, address account) external override onlyWhitelisted returns (bool) {
    return _synchroNostro(bank, account);
  }

  function decidePendingTransfer(TransferId id, TransferStatus status, string memory reason) external override onlyWhitelisted returns (bool) {
    return _decidePendingTransfer(id, status, reason);
  }

}