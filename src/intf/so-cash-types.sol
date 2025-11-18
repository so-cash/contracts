// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

/** Just a marker type - to give a type to a contract - it should not have function */
interface ISoCashBank {}

/** Just a marker type - to give a type to a contract - it should not have function */
interface ISoCashAccount {}

struct CorrespondentBank {
    bool registered;
    ISoCashAccount loro; // the account of this bank with us
    ISoCashAccount nostro; // our account with this bank
    uint256 lastNostroBalance; // the local copy of the balance of nostro account
}
type BankCode is bytes5;
type BranchCode is bytes5;
type IBAN is bytes32;
type BIC is bytes11;
type CCY is bytes3;
type AccountNumber is uint32;

struct RecipientInfo {
    ISoCashAccount account; // optional if the rest is given
    BIC bic; // optional if the account is given
    IBAN iban; // optional if the account is given
}

enum TransferStatus { 
    NEW, STP, 
    /* evnt generated from that level */
    PENDING, CANCELLED, PROCESSED 
}

struct TransferInfo {
    ISoCashAccount sender;
    RecipientInfo recipient;
    uint256 amount;
    TransferStatus status;
    string details;
    string reason;
}

type TransferId is uint256;
enum OperationDirection { DEBIT, CREDIT }

bytes32 constant ACCOUNT_NAME = "name";
bytes32 constant AUTO_TRANSFER_BELOW = "autoTransferBelow";
bytes32 constant OVERDRAFT_AMOUNT = "overdraftAmount";

ISoCashAccount constant ZERO_ACCOUNT = ISoCashAccount(address(0));
ISoCashBank constant ZERO_BANK = ISoCashBank(address(0));
