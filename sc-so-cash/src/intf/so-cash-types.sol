// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {BankAccount, BankModel, CodeType} from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";


/** Just a marker type - to give an abstract type to a contract that represents a bank module - it should not have function */
interface ISoCashBank {}

/** Just a marker type - to give an abstract type to a contract that represents a bank account - it should not have function */
interface ISoCashAccount {}

// Nostro Account is the structure that point to where the bank has its money either in a so-cash account or in an ERC20 account
struct NostroAccount {
    BankModel model; // 0: not defined, 1: so-cash account, 2: ERC20 account
    address bank; // the address of the bank or the ERC20 contract
    address account; // our account with this bank or the address to represent the ERC20 account (expected to be the address of CurrencyModule)
    int256 lastBalance; // the local copy of the balance of loro account
    int256 lastAdviceAmount; // the last edit received
    uint lastBlock; // to be replaced by a unique transactionID
}

type IBAN is bytes32;
type BIC is bytes11;
type CCY is bytes3;
type AccountNumber is uint32;

struct AccountData {
  bool registered;
  bool active;
  AccountNumber accountNumber;
  uint256 balance;
  uint256 lockedBalance;
  uint256 overdraftBalance;
  // ISoCashBank loroOf; // can remain zero if not for a bank - replaced by an attribute in the account
}

// TODO: fix typo in the name
struct RecipentInfo {
    ISoCashAccount account; // optional if the rest is given
    BIC bic; // optional if the account is given
    IBAN iban; // optional if the account is given
}

enum TransferStatus { 
    NEW, STP, 
    /* evnt generated from that level */
    PENDING, CANCELLED, PROCESSED 
}

enum ActionType { MINT, BURN, TRANSFER }

struct TransferInfo {
    ISoCashAccount sender;
    RecipentInfo recipient;
    uint256 valueTime; // equivalent to the value date in the banking world
    uint256 amount;
    TransferStatus status;
    string details;
    string reason;
}

// structure to define how the transfer should be executed in the bank
// this should be returned by the bank execution engine
struct ExecutionPlan {
    TransferId transferId;
    ISoCashAccount debitLocalAccount ; // can be zero
    ISoCashAccount creditLocalAccount; // can be zero
    ISoCashAccount payFromNostro; // can be zero
    ISoCashBank payViaBank; // can be zero
    BankAccount payViaAccount; // our account. can be undefined
    BankAccount payToAccount; // their ssi account, can be undefined
}

struct FXExecutionPlan {
    ISoCashAccount debitFromAccount; 
    ISoCashAccount creditFxProviderAccount;
    ISoCashAccount debitFxProviderAccount;
    ISoCashAccount creditToAccount;
}

type TransferId is uint256;
enum OperationDirection { DEBIT, CREDIT }

struct FXRate {
    uint256 rate; // expressed as 1 base = rate quote / 10,000
    uint256 rateTime; // timestamp of the rate creation
    uint256 expiryTime; // timestamp of the rate validaity
    CCY base;
    CCY quote;
}

bytes32 constant ACCOUNT_NAME = "name";
bytes32 constant AUTO_TRANSFER_BELOW = "autoTransferBelow";
bytes32 constant OVERDRAFT_AMOUNT = "overdraftAmount";
bytes32 constant SO_CASH_BANK = "soCashBank";

ISoCashAccount constant ZERO_ACCOUNT = ISoCashAccount(address(0));
ISoCashBank constant ZERO_BANK = ISoCashBank(address(0));