// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IERC20Internal} from "@fever-tokens/diamond/src/token/ERC20/IERC20Internal.sol";
import "./so-cash-types.sol";
import {BankIdentifier, BankAccount} from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";

import {IWhitelistedSenders} from "./whitelisted-senders.sol";

/// @title IERC20 Compatibility Metadata
/// @notice Interface for ERC20 compatibility metadata
/// @dev This interface is used by the bank modules to provide metadata for partial ERC20 compatibility
interface IERC20CompatibilityMetadata {
    /// @notice Get the name of the account
    /// @dev Get the name of the account for developers
    /// @return The name of the account
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/**
    * @title IERC20 Compatibility Base Internal
    * @notice Interface for ERC20 compatibility, simply inherit from [IERC20Internal](./api-IERC20Internal)
    * @dev This interface may be deprecated in a future version
 */
interface IERC20CompatibilityBaseInternal is IERC20Internal {
}

/**
    * @title IERC20 Compatibility Base
    * @notice Interface for ERC20 compatibility
    * @dev This interface redeclare the [IERC20Base](./api-IERC20Base) interface to fix an import issue. Will be removed in a future version
 */
interface IERC20CompatibilityBase is IERC20CompatibilityBaseInternal {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
}

/**
    * @title IERC20 Compatibility
    * @notice Interface for ERC20 compatibility
    * @dev This interface is used by the bank modules to provide ERC20 compatibility
    <br>It inherits from [IERC20CompatibilityBaseInternal](./api-IERC20CompatibilityBaseInternal) and [IERC20CompatibilityMetadata](./api-IERC20CompatibilityMetadata)
 */
interface IERC20Compatibility is IERC20CompatibilityBaseInternal, IERC20CompatibilityMetadata{
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/**
    * @title ISoCashBankIdentity interface 
    * @notice Interface to get the identity of a bank module
    * @dev This interface exposes read only methods to get the identity of a bank module
 */
interface ISoCashBankIdentity {
    /// @notice Get the version of the implementation
    /// @dev Semver syntax is expected.
    /// @return "1.0.0" or "2.0.0" currently. The Diamond implementation starts at "2.0.0". 
    function version () external view returns (string memory);

    /**
        * @notice Get the BIC of the bank
        * @dev This is also returned by the `name()` method of the ERC20 compatibility
        * @return The BIC of the bank
     */
    function bic() external view returns (string memory);
    /**
        * @notice Get the bankCode and branchCode of the bank
        * @dev This is deprecated and should be replaced by the `bankIdentifier()` method
        * @return bankCode The bankCode of the bank
        * @return branchCode The branchCode of the bank
     */
    function codes() external view returns (CodeType bankCode, CodeType branchCode);
    /**
        * @notice Get the bank identifier of the bank
        * @return id The bank identifier of the bank
     */
    function bankIdentifier() external view returns (BankIdentifier memory id);
}

/**
    * @title ISoCashBankBalanceManagementInternal interface 
    * @notice Interface for exposing events related to account and balance management
 */
interface ISoCashBankBalanceManagementInternal {
    /**
        * @notice Event emitted when an account is registered or unregistered
        * @param account The account that is registered or unregistered
        * @param registered True if the account is registered, false if it is unregistered
     */
    event AccountRegistration(ISoCashAccount indexed account, bool registered);
    /**
        * @notice Event emitted when an account is activated or deactivated
        * @dev An account is activated/deactivated by the bank back office when there are business or compliance reason to do so
        <br>An innactive account can not receive or send funds, it places the funds in a pending state for the bank back office to intervene
        * @param account The account that is activated or deactivated
        * @param active True if the account is activated, false if it is deactivated
     */
    event AccountActivation(ISoCashAccount indexed account, bool active);

    /**
        * @notice Event emitted when the balance of one or two accounts are updated
        * @dev The `Transfer()` event of the ERC20 standard is also emitted in // for compatibility
        <br>This event provides access to the transfer id that offers info about the transfer via the `transferInfo()` method of [ISoCashBankExternalWOTransfer](./api-ISoCashBankExternalWOTransfer) interface
        <br>`from`and `to` are only accounts held in this bank module (or zero account), like in the ERC20 standard and only represents the local account entries
        <br>For interbank transfers, the information of the end to end information is provided by the `transferInfo()` method.
        * @param from The account that is debitted
        * @param to The account that is credited
        * @param value The amount of the transfer expressed in the smallest unit of the currency
        * @param id The unique identifier of the transfer. Current implementation uses a counter but do not rely on this.
     */
    event TransferEx(ISoCashAccount indexed from, ISoCashAccount indexed to, uint256 value, TransferId indexed id);
}

/**
    * @title ISoCashBankBalanceManagement interface 
    * @notice Interface for exposing account balance information
    * @dev This interface exposes read only methods to get the balance of an account
    <br>Inherits from [ISoCashBankBalanceManagementInternal](./api-ISoCashBankBalanceManagementInternal).
 */
interface ISoCashBankBalanceManagement is ISoCashBankBalanceManagementInternal {
    /**
        * @notice Get the locked balance of an account
        * @dev The locked balance is the amount that has been earmarked for specific transactions by the account owner (or the bank)
        * @param account The account to get the locked balance of
        * @return The locked balance of the account
     */
    function lockedBalanceOf(ISoCashAccount account) external view returns (uint256);
    /**
        * @notice Get the unlocked balance of an account
        * @dev The unlocked balance is the amount that is immediatly available for the account owner to spend
        * @param account The account to get the unlocked balance of
        * @return The unlocked balance of the account
     */
    function unlockedBalanceOf(ISoCashAccount account) external view returns (uint256);
    /**
        * @notice Get the full balance of an account
        * @dev The full balance is the actual liability of the bank towards the account holder. It can be negative it the account is in overdraft.
        <br>Note that the `balanceOf()` method of the ERC20 standard is also available in the bank module via the interface [IERC20Compatibility](./api-IERC20Compatibility).
        * @param account The account to get the full balance of
        * @return The full balance of the account
     */
    function fullBalanceOf(ISoCashAccount account) external view returns (int256);

    /**
        * @notice get the account number for an account smart contract
        * @param account The account to get the account number of
        * @return The account number of the account or zero if not found
     */
    function accountNumberOf(ISoCashAccount account) external view returns (AccountNumber);

    /**
        * @notice get the account address for an account number
        * @param accountNumber The account number to get the account address of
        * @return The account address of the account number or zero if not found
     */
    function addressOf(AccountNumber accountNumber) external view returns (ISoCashAccount);

    /**
        * @notice get the account address for an account string as present in an IBAN
        * @param account The account part of the IBAN to get the account address of
        * @return The account address of the account of zero if not found
     */
    function addressOfFullAccount(string memory account) external view returns (ISoCashAccount);

}

/**
    * @title ISoCashBankExternalTransfer interface 
    * @notice Interface for transfer request by account smart contracts
    * @dev This interface exposes a method to transfer funds from a caller account to a recipient account
 */
interface ISoCashBankExternalTransfer {
    /**
        * @notice Transfer funds from the caller account to a recipient account
        * @dev This method can only be called by a smart contract that is registered as an account in the bank module
        <br>Events Transfer and TransferEx are emitted
        * @param to The recipient account to transfer the funds to
        * @param amount The amount of the transfer expressed in the smallest unit of the currency
        * @param details The details of the transfer
        * @return true if the transfer is successful, false otherwise
     */
    function transfer(RecipentInfo calldata to, uint256 amount, string calldata details) external returns (bool);
}

/**
    * @title ISoCashBankExternalWOTransfer interface 
    * @notice Interface for external parties (clients, 3rd parties) to interact with the bank module, excluding transfer functions
    * @dev This interface exposes functions that do not relate to transfers. These functions are in the [ISoCashBankExternalTransfer](./api-ISoCashBankExternalTransfer) or [ISoCashInterBank](./api-ISoCashInterBank) interfaces.
    <br>Inherits from [IERC20Compatibility](./api-IERC20Compatibility) and [ISoCashBankIdentity](./api-ISoCashBankIdentity) and [ISoCashBankBalanceManagement](./api-ISoCashBankBalanceManagement).
 */
interface ISoCashBankExternalWOTransfer is IERC20Compatibility, ISoCashBankIdentity, ISoCashBankBalanceManagement {
    /**
        * @notice Get the record of the transfer with the given id
        * @dev This method is used to get the information of a transfer
        <br>The `TransferInfo` structure is defined as follow:<br>
| Field          | Description                                                                                                              |<nl>
|----------------|--------------------------------------------------------------------------------------------------------------------------|<nl>
| `sender`       | The account that initiated the transfer                                                                                   |<nl>
| `recipient`    | The recipient of the transfer                                                                                            |<nl>
| `valueTime`    | The time to consider the interest calculation. The actual time of the transfer is the block timestamp defined by the TransferEx event |<nl>
| `amount`       | The amount of the transfer expressed in the smallest unit of the currency                                                 |<nl>
| `status`       | The status of the transfer and can be `NEW=0`, `STP=1`, `PENDING=2` (when stopped by the BO), `CANCELLED=3`, `PROCESSED=4`|<nl>
| `details`      | The details of the transfer                                                                                              |<nl>
| `reason`       | The reason of the status of the transfer when put in pending, cancelled or processed                                                                                 |<nl>
        * @param id The unique identifier of the transfer
        * @return The record of the transfer
     */
    function transferInfo(TransferId id) external view returns (TransferInfo memory);

    /**
        * @notice Function to lock a balance instructed by the account smart contract only
        * @dev The sender should be a registered account
        * @param amount The amount to lock
        * @return true if the lock is successful, exception otherwise
     */
    function lockFunds(uint256 amount) external returns (bool);

    /**
        * @notice Function to unlock a balance instructed by the account smart contract only
        * @dev The sender should be a registered account
        * @param amount The amount to unlock
        * @return true if the unlock is successful, exception otherwise
     */
    function unlockFunds(uint256 amount) external returns (bool);

    /**
        * @notice Get the IBAN of the account
        * @dev Implementation should return a valid IBAN that includes the bank codes and the account number.
        * @return The balance of the account
     */
    function ibanOf(ISoCashAccount account) external view returns (string memory);

    /**
        * @notice Decode an IBAN to get the bank and account
        * @dev Implementation should return the bank and account that are represented by the IBAN
        <br>The implementation should try to decode the IBAN even when it is in another bank module, using the referential if needed
        * @param iban The IBAN to decode
        * @return bank The bank that holds this account
        * @return account The account that is represented by the IBAN
     */
    function decodeIBAN(string memory iban) external view returns (ISoCashBank bank, ISoCashAccount account);
}

/**
    * @title ISoCashBankExternal interface 
    * @notice Interface for external parties (clients, 3rd parties) to interact with the bank module
    * @dev This interface exposes functions that relate to transfers and non transfer services.
    <br>Inherits from [ISoCashBankExternalWOTransfer](./api-ISoCashBankExternalWOTransfer) and [ISoCashBankExternalTransfer](./api-ISoCashBankExternalTransfer).
 */
interface ISoCashBankExternal is ISoCashBankExternalWOTransfer, ISoCashBankExternalTransfer {
}

/**
    * @title ISoCashBankPaymentInternal interface 
    * @notice Interface for exposing events related to interbank payments 
 */
interface ISoCashBankPaymentInternal {
    /**
        * @notice Event emitted by a bank that receives a notification of debit/credit on an account it owns in another bank 
        * @dev This notification is done via the `advice()` method in the [ISoCashInterBank](./api-ISoCashInterBank) interface
        * @param target The bank that receives the advice, always the bank that emits the event
        * @param account The account that is debitted or credited in the other bank
        * @param amount The amount of the advice (always positive)
        * @param direction The direction of the advice, `DEBIT=0` or `CREDIT=1`
        * @param id The unique identifier of the transfer related to the advice in the calling bank
     */
    event Adviced(ISoCashBank indexed target, ISoCashAccount indexed account, uint256 amount, OperationDirection direction, TransferId indexed id);

}

/**
    * @title ISoCashInterBank interface 
    * @notice Interface for relations between bank modules that have a correspondent relationship
    * @dev This interface exposes methods to coordinate interbank transfers and advices
    <br>Inherits from [ISoCashBankPaymentInternal](./api-ISoCashBankPaymentInternal).
 */
interface ISoCashInterBank is ISoCashBankPaymentInternal{
    /**
        * @notice The calling bank requests the executing bank to transfer funds to a recipient account.
        * @dev The calling bank should be a correspondent of the executing bank.
        <br>The executing bank will need to check that it has been paid in the `ssi` account before performing the transfer. To do this several methods are possible:
        <br>- Keeping a record of the last balance of that account in the state of the bank module so to compare it with the actual balance
        <br>- Other means to be determined
        * @param ssi The SSI of the executing bank where the same amount should have been paid
        * @param to The recipient account to transfer the funds to
        * @param amount The amount of the transfer expressed in the smallest unit of the currency
        * @param id The unique identifier of the transfer in the calling bank
        * @return true if the transfer is successful, false or fail otherwise
     */
    function interbankTransfer(BankAccount calldata ssi, RecipentInfo calldata to, uint256 amount, TransferId id) external returns (bool);
    /**
        * @notice Special function to request the executing bank to agree on a netting between accounts they hold with each other
        * @dev The calling bank should be a correspondent of the executing bank.
        <br>The executing bank will need to check that its account has been reduced by the amount before performing the reduction of the caller account.
        * @param amount The amount of the netting expressed in the smallest unit of the currency
        * @param id The unique identifier of the netting in the calling bank
        * @return true if the netting is successful, false or fail otherwise
     */
    function interbankNetting(uint256 amount, TransferId id) external returns (bool);

    /**
        * @notice The executing bank receives an advice from the calling bank that its account has been debitted or credited
        * @dev The calling bank should be a correspondent of the executing bank.
        <br>The executing bank will check that it has an account with the calling bank, check that the copy of the balance it has match with the difference of the advice amount
        and update the copy of its balance.
        * @param amount The amount of the advice (always positive)
        * @param direction The direction of the advice, `DEBIT=0` or `CREDIT=1`
        * @param id The unique identifier of the transfer related to the advice in the calling bank
        * @return true if the advice is successful, false or fail otherwise
     */
    function advice(uint256 amount, OperationDirection direction, TransferId id) external returns (bool);
}

/**
    * @title ISoCashBankTransferManagementInternal interface 
    * @notice Interface for exposing events related to the management of transfers that require manual intervention
 */
interface ISoCashBankTransferManagementInternal {
    /**
        * @notice Event emitted when the status of a transfer is `PENDING`, `CANCELLED` or `PROCESSED`
        * @dev This event is emitted when the bank module decides to put a transfer in pending, and then when the back office decides to cancel or process it
        * @param id The unique identifier of the transfer to retrieve the informations
        * @param status The status of the transfer, `PENDING=2`, `CANCELLED=3`, `PROCESSED=4`
     */
    event TransfertStateChanged(TransferId indexed id, TransferStatus status);
}

/**
    * @title ISoCashBankNostroManagementInternal interface
    * @notice Interface for exposing events related to the management of nostro accounts
 */
interface ISoCashBankNostroManagementInternal {
    /**
        * @notice Event emitted when a nostro account is registered or unregistered
        * @dev This event is emitted when the back office calls the `registerNostroAccount()` or `unregisterNostroAccount()` methods
        * @param model The model of the nostro account, `UNDEFINED=0`, `SO_CASH=1`, `ERC20=2`
        * @param bank The bank that holds the nostro account, or the address of the ERC20 token
        * @param account The address of the account balance (either a so|cash account or an ERC20 address that holds the balance)
        * @param registered True if the account is registered, false if it is unregistered
     */
    event NostroAccountRegistration(BankModel model, address indexed bank, address indexed account, bool registered);

}

/**
    * @title ISoCashBackOfficePayments interface
    * @notice Interface for the back office to manage payments
    * @dev This interface exposes methods to manage payments with a wallet that is whitelisted as a back office
 */
interface ISoCashBackOfficePayments {
    /**
        * @notice Initiate a transfer from the back office side on behalf of a client
        * @dev This method requires that the caller is whitelisted
        * @param from The account to transfer the funds from
        * @param to The recipient account to transfer the funds to
        * @param amount The amount of the transfer expressed in the smallest unit of the currency
        * @param details The details of the transfer
        * @return true if the transfer is successful, false or fail otherwise
        */
    function transferFrom(ISoCashAccount from, RecipentInfo calldata to, uint256 amount, string calldata details) external returns (bool);
    /**
        * @notice request another bank that holds a nostro account to operate a netting
        * @dev This method requires that the caller is whitelisted
        * @param correspondent The bank module that holds the nostro account
        * @param loro The account of the correspondent with the caller bank where the netting should be operated
        * @param amount The amount of the netting expressed in the smallest unit of the currency
        * @return true if the netting is successful, false or fail otherwise
        */
    function requestNetting(ISoCashBank correspondent, ISoCashAccount loro, uint256 amount) external returns (bool);

    /**
        * @notice Forces the update of the copy of a nostro balance in the bank module
        * @dev This method requires that the caller is whitelisted
        <br>The nostro account can be a so|cash account or an ERC20 token account
        * @param bank The bank that holds the nostro account or the address of the ERC20 token
        * @param account The address of the account balance
        * @return true if the update is successful, false or fail otherwise
     */
    function synchroNostro(address bank, address account) external returns (bool);

    /**
        * @notice Instruct the bank module to proceed with a pending transfer or to cancel it
        * @dev This method requires that the caller is whitelisted
        * @param id The unique identifier of the transfer
        * @param status The status of the transfer, `CANCELLED=3`, `PROCESSED=4`
        * @param reason The reason of the status of the transfer when put in pending, cancelled or processed
        * @return true if the decision is successful, false or fail otherwise
     */
    function decidePendingTransfer(TransferId id, TransferStatus status, string memory reason) external returns (bool);
}

/**
    * @title ISoCashBankBackOfficeServices interface
    * @notice Interface for the back office to accounts, nostros and local credit and debits.
    * @dev This interface exposes methods for whitelisted back office wallets. 
 */
interface ISoCashBankBackOfficeServices {
    /**
        * @notice Event emitted when the module is created
        * @dev Deprecated: Prefer the event `BankModuleSet` emitted at registration in the referential in [ISoCashCountryStateManagement](./api-ISoCashCountryStateManagement)
        * @param bank The bank module that is created
        * @param bic The BIC of the bank
        * @param currency The currency of the bank
     */
    event BankCreation(ISoCashBank indexed bank, string bic, string currency);
    /**
        * @notice Event emitted when the bank module is Registered
        * @dev Deprecated (and not emitted in Diamond implementation). Use `BankModuleSet` emitted at registration in the referential in [ISoCashCountryStateManagement](./api-ISoCashCountryStateManagement)
        * @param bank The bank module that is registered
        * @param registered True if the bank is registered, false if it is unregistered
     */
    event BankRegistration(ISoCashBank indexed bank, bool registered);

    /**
        * @notice Test if the bank module is a correspondent of this bank module
        * @dev implemented normally via the referential but can be overriden
        * @param correspondent The bank module to test
        * @return true if the bank module is a correspondent, false otherwise
     */
    function isCorrespondentRegistered(ISoCashBank correspondent) external view returns (bool);

    /** 
        * @notice Get the correspondent bank identifier of a correspondent bank module
        * @dev This method is used to get the correspondent bank identifier of a correspondent bank module
        * @param correspondent The correspondent bank module
        * @return cb The correspondent bank identifier of the correspondent bank module
     */
    function correspondent(ISoCashBank correspondent) external view returns (BankIdentifier memory cb);


    /**
        * @notice Register an account smart contract as an account of the bank module
        * @dev Only whitelisted back office wallets can call this method.
        <br>The bank module should have been given ownership of the account smart contract before the call (`transferOwnership()`).
        <br>Client can provide their own smart contract to the bank to be registered as an account as long as it respects the bank requirements.
        * @param account The account to register
        * @return true if the account is registered, false otherwise
     */
    function registerAccount(ISoCashAccount account) external returns (bool);
    /**
        * @notice Unregister an account smart contract as an account of the bank module
        * @dev Only whitelisted back office wallets can call this method.
        <br>The bank module should transfer the ownership to the caller wallet during the execution so that the back office can return the ownership to the client.
        * @param account The account to unregister
        * @return true if the account is unregistered, false otherwise
     */
    function unregisterAccount(ISoCashAccount account) external returns (bool);
    /**
        * @notice Test if an account is registered as an account of the bank module
        * @param account The account to test
        * @return true if the account is registered, false otherwise
     */
    function isAccountRegistered(ISoCashAccount account) external view returns (bool);
    /**
        * @notice Activate or deactivate an account
        * @dev Only whitelisted back office wallets can call this method.
        * @param account The account to activate or deactivate
        * @return true if the account is now active and false if it is now deactivated
     */
    function toggleAccountActive(ISoCashAccount account) external returns (bool);
    /**
        * @notice Test if an account is active
        * @param account The account to test
        * @return true if the account is active, false otherwise
     */
    function isAccountActive(ISoCashAccount account) external view returns (bool);

    /**
        * @notice Register a nostro account
        * @dev Only whitelisted back office wallets can call this method.
        <br>A nostro account is either a so|cash account or an ERC20 token account that holds the balance of the bank module in another bank module.
        * @param nostro The nostro account to register
        * @return true if the account is registered, false otherwise
     */
    function registerNostroAccount(BankAccount calldata nostro) external returns (bool);
    /**
        * @notice Unregister a nostro account
        * @dev Only whitelisted back office wallets can call this method.
        <br>There is currently only one nostro account per bank module but the interface allows for multiple accounts.
        * @param bank The bank that holds the nostro account
        * @param account The address of the account balance
        * @return true if the account is unregistered, false otherwise
     */
    function unregisterNostroAccount(address bank, address account) external returns (bool);
    /**
        * @notice Get the model of a nostro account
        * @param bank The bank that holds the nostro account
        * @param account The address of the account balance
        * @return The model of the nostro account : `UNDEFINED=0`, `SO_CASH=1`, `ERC20=2`
     */
    function nostroAccountModel(address bank, address account) external view returns (BankModel);
    /**
        * @notice Get the actual balance of a nostro account and the last copy in the bank module
        * @param bank The bank that holds the nostro account
        * @param account The address of the account balance
        * @return actual The actual balance of the account in the bank that holds the account
        * @return last The last copy of the balance of the account in this bank module
     */
    function getNostroBalance(address bank, address account) external view returns (int256 actual, int256 last);

    /**
        * @notice Credit the account with new funds coming from money received in bank nostro or from a loan or equivalent
        * @dev Accounting wise, the account is only a liability side, so when recording a credit, the bank should record a debit in an asset account.
        Such asset account can be a nostro account, held on-chain or outside the blockchain, or can be against the recognition of money that the client owes to the banks (payable, loan, ...).
        <br>Only whitelisted back office wallets can call this method.
        * @param account The account to credit
        * @param amount The amount to credit
        * @param details The details of the credit
        * @return true if the credit is successful, false or fail otherwise
     */
    function credit(ISoCashAccount account, uint256 amount, string calldata details) external returns (bool);
    /**
        * @notice Debit the account reducing the liability to the client against an asset of the bank
        * @dev Accounting wise, the account is only a liability side, so when recording a debit, the bank should record a credit in an asset account.
        Such asset account can be a nostro account, held on-chain or outside the blockchain, or can be against the recognition of money that the client owes to the banks (payable, loan, ...).
        <br>Only whitelisted back office wallets can call this method.
        * @param account The account to debit
        * @param amount The amount to debit
        * @param details The details of the debit
        * @return true if the debit is successful, false or fail otherwise
     */
    function debit(ISoCashAccount account, uint256 amount, string calldata details) external returns (bool);
    /**
        * @notice Locks some funds of the client
        * @dev The locked funds are not usable by the client for spending but are still part of the full balance of the account
        <br>Note that this function is not to be confused with the `lockFunds(amount)` method of the [ISoCashBankExternalWOTransfer](./api-ISoCashBankExternalWOTransfer) interface.
        <br>Only whitelisted back office wallets can call this method.
        * @param account The account to lock the funds of
        * @param amount The amount to lock
        * @return true if the lock is successful, false or fail otherwise
     */
    function lockFunds(ISoCashAccount account, uint256 amount) external returns (bool);
    /**
        * @notice Unlocks some funds of the client
        * @dev The unlocked funds are usable by the client for spending and are part of the full balance of the account
        <br>Note that this function is not to be confused with the `unlockFunds(amount)` method of the [ISoCashBankExternalWOTransfer](./api-ISoCashBankExternalWOTransfer) interface.
        <br>Note that this function can unlock funds locked by the client via the HTLC protocol.
        <br>Only whitelisted back office wallets can call this method.
        * @param account The account to unlock the funds of
        * @param amount The amount to unlock
        * @return true if the unlock is successful, false or fail otherwise
     */
    function unlockFunds(ISoCashAccount account, uint256 amount) external returns (bool);
}

/**
    * @title ISoCashBankbackOffice interface
    * @notice Interface for the back office to manage the bank module
    * @dev This interface groups events and functions from 
    [ISoCashBankBackOfficeServices](./api-ISoCashBankBackOfficeServices), 
    [ISoCashBackOfficePayments](./api-ISoCashBackOfficePayments), 
    [ISoCashBankTransferManagementInternal](./api-ISoCashBankTransferManagementInternal), 
    [ISoCashBankNostroManagementInternal](./api-ISoCashBankNostroManagementInternal) and 
    [ISoCashBankBalanceManagementInternal](./api-ISoCashBankBalanceManagementInternal).
 */
interface ISoCashBankBackOffice is ISoCashBankBackOfficeServices, ISoCashBackOfficePayments, ISoCashBankTransferManagementInternal, ISoCashBankNostroManagementInternal, ISoCashBankBalanceManagementInternal{
}

/**
    * @title ISoCashBankExplainPlan interface
    * @notice Interface for debugging the execution plan of a transfer
    * @dev This interface exposes an event that is not a public api purpose but is usefull for debugging the execution plan
    <br>An `ExecutionPlan` structure indicates what action the bank module needs to do to execute a transfer. It is defined as follow:<br>
| Field          | Description                                                                                                              |<nl>
|----------------|--------------------------------------------------------------------------------------------------------------------------|<nl>
| `transferId`   | The unique identifier of the transfer                                                                                     |<nl>
| `debitLocalAccount` | The account that should be debitted in the local bank module. Can be Zero.                                              |<nl>
| `creditLocalAccount` | The account that should be credited in the local bank module. Can be Zero.                                              |<nl>
| `payFromNostro` | The nostro account that should be used to pay the beneficiary directly. Zero if interbank transfer is needed.        |<nl>
| `payViaBank`   | The correspondent bank via which the payment should be done. Zero not needed.                                           |<nl>
| `payViaAccount` | The nostro account to use to credit the correspondent bank `payToAccount`                                              |<nl>
| `payToAccount` | The account of the `payViaBank` that should be credited. Always present if `payViaAccount` is present.                 |<nl>

<br> 
<br>The business logic for interpreting the plan is as follow:
<br>- If `debitLocalAccount` is not Zero, this account, that is local, is debitted
<br>- If `creditLocalAccount` is not Zero, this account, that is local, is credited
<br>- If `payFromNostro` is not Zero, the beneficiary is paid by a transfer from this nostro account. The bank instruct the transfer directly on its account.
<br>- If `payViaBank` is not Zero, then the bank relies on the correspondent bank to pay the beneficiary using the `interbankTransfer()` method.
<br>    - If the `creditLocalAccount` was credited, it was the account of th correspondent, to trigger the interbank transfer
<br>    - Else, the bank execute a transfer its `payViaAccount` account to the `payToAccount` of the correspondent and then trigger the interbank transfer.

 */
interface ISoCashBankExplainPlan {
    /**
        * @notice Event emitted (optionally) when the bank performs a transfer.
     */
    event ExplainPlan(ExecutionPlan plan);
}

/**
    * @title ISoCashBankPaymentSimulation interface
    * @notice Interface for simulating the execution plan of a transfer
    * @dev This interface exposes methods to simulate the execution plan of a transfer. Its implementation is not mandatory and discourage in production environment.
 */
interface ISoCashBankPaymentSimulation {
    /**
        * @notice Simulate a transfer from an account in this bank module to a recipient
        * @param fromAccount The account to transfer the funds from
        * @param to The recipient of the transfer
        * @param amount The amount of the transfer expressed in the smallest unit of the currency
        * @return The execution plan of the transfer
     */
    function simulateTransfer(ISoCashAccount fromAccount, RecipentInfo memory to, uint256 amount) external view returns (ExecutionPlan memory);
    /**
        * @notice Simulate the processing of a transfer instruction received from antoher bank module
        * @param fromBank The bank module sending the transfer instruction
        * @param to The recipient of the transfer
        * @param amount The amount of the transfer expressed in the smallest unit of the currency
        * @return The execution plan of the transfer
     */
    function simulateInterbankTransfer(ISoCashBank fromBank, RecipentInfo memory to, uint256 amount) external view returns (ExecutionPlan memory);
}

/**
    * @title ISoCashBankFull interface
    * @notice Interface for the full bank module
    * @dev This interface groups all the interfaces of the bank module
    [IWhitelistedSenders](./api-IWhitelistedSenders),
    [ISoCashBankExternal](./api-ISoCashBankExternal),
    [ISoCashInterBank](./api-ISoCashInterBank),
    [ISoCashBankBackOffice](./api-ISoCashBankBackOffice),
    <br> and optionnally: 
    [ISoCashBankPaymentSimulation](./api-ISoCashBankPaymentSimulation),
    [ISoCashBankExplainPlan](./api-ISoCashBankExplainPlan)
    <br> It also exposes the `owner()` method to get the owner of the bank module.
 */
interface ISoCashBankFull is IWhitelistedSenders, ISoCashBankExternal, ISoCashInterBank, ISoCashBankBackOffice, ISoCashBankPaymentSimulation, ISoCashBankExplainPlan {
    function owner() external view returns (address) ;
}


/**
    * @title ISoCashFXProviderInternal interface 
    * @notice Interface for exposing events related to FX settlement and account association
 */
interface ISoCashFXProviderInternal {
    /**
        * @notice Event emitted when a currency account is set in the FX provider smart contract
        * @param ccy The currency of the account
        * @param account The account that is set
     */
    event CurrencyAccountSet(CCY indexed ccy, ISoCashAccount account);
    /**
        * @notice Event emitted when the FX Provider smart contract settle the operation
        * @param from The account that is debitted in the base currency
        * @param to The account that is credited in the quote currency
        * @param amount The amount of the transfer expressed in the smallest unit of the base currency
        * @param rate The FX rate used for the settlement expressed as a rate of the quote currency in the base currency * 10,000.
     */
    event FXSettlement(ISoCashAccount indexed from, ISoCashAccount indexed to, uint256 amount, uint256 rate);
}


/**
    * @title ISoCashFXProvider interface 
    * @notice Interface for FX settlement and account association
    * @dev This interface exposes methods to manage an FX Provider smart contract
    <br>Inherits from [ISoCashFXProviderInternal](./api-ISoCashFXProviderInternal).
    <br>An FXProvider smart contract is a simple solution to execute atomically two transfers in two different currencies with a rate signed by an external private key and valid for a certain amount of time.
    <br>The smart contract is expose to its users and therefore offers features to get a rate from an external API (`getFXRateSource()`).
    <br>The smart contract handles [FXRate](./api-t-FXRate) structures that are signed by a private key and verified by the smart contract.
    <br>This structures is defined as follow:<br>
| Field          | Description                                                                                                              |<nl>
|----------------|--------------------------------------------------------------------------------------------------------------------------|<nl>
| `rate`         | The rate value in decimal form (1 base unit = rate quote unit * 10,000) - To be adjusted according to currency decimals                                                            |<nl>
| `rateTime`     | The timestamp when the rate was created, in seconds                                                                      |<nl>
| `expiryTime`   | The timestamp when the rate will expire, in seconds                                                                      |<nl>
| `base`      | The base currency of the rate                                                                                            |<nl>
| `quote`     | The quote currency of the rate                                                                                           |<nl>

 */
interface ISoCashFXProvider is ISoCashFXProviderInternal{
    /**
        * @notice Set the account of a currency in the FX Provider smart contract
        * @dev Only a whitelisted wallet of FX Provider smart contract can call this method.
        * @param ccy The currency of the account
        * @param account The account to set. The FXProvider smart contract should be whitelisted on the account
     */
    function setCurrencyAccount(CCY ccy, ISoCashAccount account) external;

    /**
        * @notice Set the FX Rate API URL for a currency pair
        * @dev Only a whitelisted wallet of FX Provider smart contract can call this method.
        <br>In the current implementation, the currencies are not used and a single api url can be set.
        <br>The API should follow the following standard: `https://<server.domain>/<path>?base=<base>&quote=<quote>&amount<amount>&origin<wallet-address-of-caller>`
        <br>It should return a JSON object with the following fields: 
<br>```js<nl>
{<nl>
  rate: number; // rate value in decimal form (1 base unit = rate quote unit)<nl>
  rateTime: number; // the timestamp when the rate was created, in seconds<nl>
  expiryTime: number; // the timestamp when the rate will expire, in seconds<nl>
  baseCcy: string; // the base currency of the rate<nl>
  quoteCcy: string; // the quote currency of the rate<nl>
  signature: string; // the signature of the rate by the rate signer as a base64 encoded string<nl>
  signerAddress: string; // the address of the rate signer in 0x123...DEF format<nl>
  requestorAddress: string; // the tx.origin of the requestor, used to create the signature (integrated in the hash)<nl>
}<nl>
        ```
        * @param base The base currency of the rate (not used in the current implementation)
        * @param quote The quote currency of the rate (not used in the current implementation)
        * @param source The URL of the API to get the rate
     */
    function setFXRateSource(CCY base, CCY quote, string calldata source) external;
    /**
        * @notice Get the FX Rate API URL for a currency pair
        * @dev Look at the `setFXRateSource()` method for more information
        * @param base The base currency of the rate
        * @param quote The quote currency of the rate
        * @return The URL of the API to get the rate
     */
    function getFXRateSource(CCY base, CCY quote) external view returns (string memory);

    /**
        * @notice Set the rate signer of the FX Provider API
        * @dev Only a whitelisted wallet of FX Provider smart contract can call this method.
        * @param signer The address of the private key that signs the rates in the API
     */
    function setRateSigner(address signer) external;
    /**
        * @notice Get the rate signer of the FX Provider API
        * @return The address of the private key that signs the rates in the API
     */
    function getRateSigner() external view returns (address);


    /**
        * @notice Calculate the hash of a FX Rate 
        * @dev The hash is `keccak256(abi.encodePacked(tx.origin, rate.base, rate.quote, rate.rate, rate.rateTime, rate.expiryTime))`
        <br>The `tx.origin` is used to prevent replay attacks and represents the address that will initiate the settlement with that rate
        <br>You can use this function to create the hash, or you can calculate it yourself off-chain.
        * @param rate The FX Rate to hash
        * @return The hash of the FX Rate
     */
    function hashOfFXRate(FXRate memory rate) external view returns (bytes32);
    /**
        * @notice Verify the signature of a FX Rate
        * @dev The signature is a bytes array of 65 bytes that represents the ecdsa signature of the hash of the rate.
        <br>The signature is created by the API providing the rate. The signature DO NOT apply ethereum signature modifications: 
        No prefix; no v = 27 or 28; no chain id; But the recovery id is 0 or 1. The `secp256k1.ecdsaSign(hash, pk)` of the https://www.npmjs.com/package/secp256k1 library.
     */
    function verifyFXRate(FXRate memory rate, bytes memory signature) external view returns (bool);

    /**
        * @notice Execute the settlement of a FX operation which rate has been obtained from the API
        * @dev The rate will be verified against the signature and the time validity
        <br>Before calling this method the caller must allow the FXProvider smart contract to spend the base currency amount from the `from` account using the `approve()` method. 
        <br>Then the FX Provider smart contract calculate the amount of the quote currency to credit to the `to` account and execute the transfer.
        <br>The transfer is done atomically, in the form on two legs of payment 
        <br>- One leg is the debit of the `from` account in the base currency; credit the base currency account of the FX Provider
        <br>- The second leg is the debit of the quote currency account of the FX Provider; credit the `to` account in the quote currency
        <br>If the FX Provider does not have enough funds in the quote currency, then the settlement fails.
        * @param from The account to debit in the base currency
        * @param to The account to credit in the quote currency
        * @param amount The amount of the transfer expressed in the smallest unit of the base currency
        * @param rate The FX rate used for the settlement
        * @param signature The signature of the rate by the rate signer
        * @param details The details of the transfer
        * @return true if the settlement is successful, false or fail otherwise
     */
    function settlement(RecipentInfo calldata from, RecipentInfo calldata to, uint256 amount, FXRate calldata rate, bytes calldata signature, string calldata details) external returns (bool);
}

/**
    * @title ISoCashFXProviderFull interface
    * @notice Interface for the full FX Provider smart contract
    * @dev This interface groups all the interfaces of the FX Provider smart contract
    [ISoCashFXProvider](./api-ISoCashFXProvider),
    [IWhitelistedSenders](./api-IWhitelistedSenders),
    [ISoCashBankIdentity](./api-ISoCashBankIdentity)
 */
interface ISoCashFXProviderFull is ISoCashFXProvider, IWhitelistedSenders, ISoCashBankIdentity {}