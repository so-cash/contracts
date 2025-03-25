// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@fever-tokens/diamond/src/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@fever-tokens/diamond/src/token/ERC20/extensions/IERC20Metadata.sol";

// import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../intf/whitelisted-senders.sol";
import "../intf/htlc-payment.sol";
import "../utilities/whitelisted-senders.sol";
import "./so-cash-types.sol";


/**
    * @title ISoCashAccountData interface for bank account
    * @notice The bank account data service is used to manage the attributes and info of a bank account in so|cash.
    * @dev This interface is used by the account owner and the bank to get and manage the attributes of the account.
 */
interface ISoCashAccountData {
  /**
      * @notice Get the bank module of the account.
      * @dev The bank is the contract that manages the account. It is also the `owner` in the [IOwnable](./api-IOwnable) sense.
      * @return The bank of the account.
   */
  function bank() external view returns (ISoCashBank);

  /**
      * @notice Get the iban of the account.
      * @dev The IBAN is the international bank account number of the account and contains the country of the bank, the bank codes and the account number.
      * @return The IBAN of the account.
   */
  function iban() external view returns(string memory);

  /**
      * @notice Get the account number of the account.
      * @dev The account number is a sequential number of the accounts created in the bank but this is not an obligation.
      <br>Implementations are free to use any kind of account number as long as it respects the IBAN standard.
      * @return The account number of the account.
   */
  function accountNumber() external view returns(AccountNumber);

  /**
      * @notice Get attribute as string
      * @dev The attributes are used to store additional info on the account.
      <br>Note that the `name`is unique for the account but can be duplicated by type of attribute.
      * @param name The name of the attribute.
      * @return The value of the attribute as a string.
   */
  function getAttributeStr(bytes32 name) view external returns(string memory);
  /**
      * @notice Set attribute as string
      * @dev The attributes are used to store additional info on the account.
      <br>Note that the `name`is unique for the account but can be duplicated by type of attribute.
      * @param name The name of the attribute.
      * @param value The value of the attribute as a string.
   */
  function setAttributeStr(bytes32 name, string memory value) external;
  /**
      * @notice Get attribute as number
      * @dev The attributes are used to store additional info on the account.
      <br>Note that the `name`is unique for the account but can be duplicated by type of attribute.
      * @param name The name of the attribute.
      * @return The value of the attribute as a number.
   */
  function getAttributeNum(bytes32 name) view external returns(int);
  /**
      * @notice Set attribute as number
      * @dev The attributes are used to store additional info on the account.
      <br>Note that the `name`is unique for the account but can be duplicated by type of attribute.
      * @param name The name of the attribute.
      * @param value The value of the attribute as a number.
   */
  function setAttributeNum(bytes32 name, int value) external;

  /**
      * @notice Get attribute as address
      * @dev The attributes are used to store additional info on the account.
      <br>Note that the `name`is unique for the account but can be duplicated by type of attribute.
      * @param name The name of the attribute.
      * @return The value of the attribute as an address.
   */
  function getAttributeAddr(bytes32 name) view external returns(address);

  /**
      * @notice Set attribute as address
      * @dev The attributes are used to store additional info on the account.
      <br>Note that the `name`is unique for the account but can be duplicated by type of attribute.
      * @param name The name of the attribute.
      * @param value The value of the attribute as an address.
   */
  function setAttributeAddr(bytes32 name, address value) external;
}


/**
    * @title ISoCashAccountActions interface for bank account
    * @notice The bank account actions service is used to operate payment from a bank account in so|cash.
    * @dev This interface is used by the account owner and the bank to manage the actions on the account.
 */
interface ISoCashAccountActions  {
  /**
      * @notice Get the balance of the account.
      * @dev The balance is the positive amount of the account. If the account is in overdraft, the balance is zero.
      <br> This function conserve ERC20 compatibility.
      * @return The balance of the account.
   */
  function balance() external view returns(uint256);

  /**
      * @notice Get the locked balance of the account.
      * @dev The locked balance is the amount of the account balance that is locked in a payment.
      <br> You can have a negative `fullBalance` and a positive `lockedBalance` if the account is in overdraft.
      * @return The locked balance of the account.
   */
  function lockedBalance() external view returns(uint256);

  /**
      * @notice Get the unlocked balance of the account.
      * @dev The unlocked balance is the amount of the account balance that is imediatly available for payment.
      <br> If the `balance` is lower than the `lockedBalance`, the `unlockedBalance` is zero, else it is the difference of the 2.
      * @return The unlocked balance of the account.
   */
  function unlockedBalance() external view returns(uint256);

  /**
      * @notice Get the full balance of the account.
      * @dev The full balance is the actual balance of the account including overdraft.
      <br> If the account is in overdraft, the full balance is negative.
      * @return The full balance of the account.
   */
  function fullBalance() external view returns(int256);

  /**
      * @notice Transfer funds to another account.
      * @dev This function is used to transfer funds to another account.
      <br>Note that the [IERC20](./api-IERC20) function `transfer()` is also available and calls this function with the details "ERC20 Transfer".
      <br>Only whitelisted senders can call this function or callers that has received an allowance.
      <br>Allowance can be provided by a whitelisted sender using the `approve()` function of [IERC20](./api-IERC20).
      <br>Note that the `recipient` is a structure where you provide either the smart contract address of the beneficiary account or its IBAN. 
      <br>If the beneficiary is a bank, the BIC can also be provided (deprecated)
      * @param recipient The recipient of the funds.
      * @param amount The amount to transfer.
      * @param details The details of the transfer.
      * @return true if the transfer is successful, false otherwise.
   */
  function transferEx(RecipentInfo calldata recipient, uint256 amount, string calldata details) external returns (bool);

  /**
      * @notice Locks an amount for a certain payment using a secret.
      * @dev This function is used to lock an amount for a certain payment using a secret following HTLC interoperability.
      <br>Only whitelisted senders can call this function.
      <br>The `recipient` has the same meaning as in `transferEx()`.
      <br>Note that because this function is a transaction, the best way to retrieve the returned id of the HTLC it via the event `HTLCPaymentCreated` defined in [IHTLCPaymentInternal](./api-IHTLCPaymentInternal).
      <br>To do this, retrieve the transaction hash of that transaction, gets the receipt and then the logs that match the block, the target smart contract and the event signature.
      <br>Because the `hashlockPaid` is unique and indexed in the event you can also filter new events with that hash.
      * @param recipient The recipient of the funds.
      * @param amount The amount to lock. It must be available in the account.
      * @param deadline The timestamp in sec when the lock expires.
      * @param hashlockPaid The hash of the secret that can trigger the payment.
      * @param hashlockCancel The hash of the secret that can cancel the payment (deprecated).
      * @param opaque The optional opaque data to be interpreted by the user according to their protocol. Typically a JSON string.
      * @return key The unique identifier of the payment. (see note above)
    */
  function lockFunds(RecipentInfo calldata recipient, uint256 amount, 
              uint256 deadline, bytes32 hashlockPaid, bytes32 hashlockCancel, 
              string calldata opaque) external returns (bytes32 key);

  /**
      * @notice Transfer locked funds to the recipient.
      * @dev This function is used to transfer locked funds to the pre-set recipient.
      <br>Anyone can call this function as long as they have the valid secret.
      <br>The `recipient` is ignored and will be removed in a future version.
      <br>The `secret` is the secret that can unlock the payment.
      <br>If successful, the HTLC `state` is set to `PAID` and the event `HTLCPaymentRemoved` is emitted revealing the secret.
      * @param key The unique identifier of the payment.
      * @param recipient The recipient of the funds. (deprecated and ignored).
      * @param secret The secret to unlock the payment.
      * @param details The details of the transfer transmitted with the payment.
      * @return true if the transfer is successful, false otherwise.
    */
  function transferLockedFunds(bytes32 key, RecipentInfo calldata recipient, string calldata secret, string calldata details) external returns (bool);

  /**
      * @notice Unlock locked funds.
      * @dev This function is used to unlock locked funds.
      <br>Only whitelisted sender can call this function.
      <br>If successful, the HTLC `state` is set to `CANCELLED` and the event `HTLCPaymentRemoved` is emitted revealing the cancel secret if present.
      <br>Note that to properly uses the cancel secret (that must be provided by the caller of the `lockFunds()` function), the `hashlockCancel` 
      must have been provided by the counterparty (and not the owner of the funds). 
      In that way, if the counterparty decide to no complete the process it can send the cancel secret to the initial holder in order to unlock the funds before the end of the deadline. 
      However, if the counterparty realizes that the lock does not contains its cancel hash (or a zero hash), 
      then it can decide not to proceed with the transaction as it can mean that the initial fund owner may have the actual secret to retrieve the funds 
      before the end of the deadline and the counterparty will not be able to retrieve the funds after completing its end of the bargain.
      * @param key The unique identifier of the payment.
      * @param secret The secret to unlock the payment.  
      * @return true if the unlock is successful, false otherwise.
   */
  function unlockFunds(bytes32 key, string calldata secret) external returns (bool);
}


/**
    * @title ISoCashOwnedAccount interface for bank account
    * @notice Exposes the functions and events for basic interactions with a bank account in so|cash.
    * @dev This interface inherits from [ISoCashAccountActions](./api-ISoCashAccountActions) and [ISoCashAccountData](./api-ISoCashAccountData) to provide the basic functions.
    <br>It also inherits from [IERC20](./api-IERC20) and [IERC20Metadata](./api-IERC20Metadata) to provide the ERC20 compatibility.
    <br>It also inherits from [ISoCashAccount](./api-ISoCashAccount) but this does not add any new function.
    <br>It is used by the [ISoCashAccountFull](./api-ISoCashAccountFull) to provide the full set of functions.
 */
interface ISoCashOwnedAccount is ISoCashAccountActions, ISoCashAccount, ISoCashAccountData, IERC20, IERC20Metadata {

}

/**
    * @title ISoCashAccountFull interface for bank account
    * @notice Exposes the functions and events for full interactions with a bank account in so|cash.
    * @dev This interface inherits from [ISoCashOwnedAccount](./api-ISoCashOwnedAccount) and [IHTLCPayment](./api-IHTLCPayment) and [IWhitelistedSenders](./api-IWhitelistedSenders) and [IOwnable](./api-IOwnable) to provide the full set of functions.
 */
interface ISoCashAccountFull is ISoCashOwnedAccount, IHTLCPayment, IWhitelistedSenders, IOwnable {}