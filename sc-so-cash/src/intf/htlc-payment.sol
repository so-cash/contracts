// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./so-cash-types.sol";

enum HTLCState {
    INITIATED,
    PAID,
    CANCELLED
}

struct HTLC {
    RecipentInfo recipient; // the expected beneficiary of the locked funds
    uint256 amount; // the amount to be repaid
    uint256 deadline; // the deadline to repay the debt in seconds
    bytes32 hashlockPaid; // the hashlock being the sha256 of the release secret
    bytes32 hashlockCancel; // the hashlock being the sha256 of the cancel secret (optional)
    string opaque; // optional opaque data to be interpreted by the user according to their protocol
    HTLCState state; // the state of the HTLC
}

/**
    * @title IHTLCPaymentInternal interface 
    * @notice The HTLC payment service for an account emits events defined in this interface.
    * @dev This interface exposes the events of the HTLC payment service.
    <br>Note the definition of the HTLC structure in the [IHTLCPayment](./api-IHTLCPayment) interface.
 */
interface IHTLCPaymentInternal {
    /**
        * @notice Emitted when a new HTLC payment is created.
        * @dev The `id` is a hash of several info to identify uniquely the structure. No specification set as long as it is unique for an account.
        * @param id The unique identifier of the HTLC payment.
        * @param hashlockPaid The hash of the secret that locks the payment.
        * @param htlc The HTLC structure.
     */
    event HTLCPaymentCreated(bytes32 indexed id, bytes32 indexed hashlockPaid, HTLC htlc);

    /**
        * @notice Emitted when a HTLC payment is paid or cancelled.
        * @dev The `id` is a hash of several info to identify uniquely the structure. No specification set as long as it is unique for an account.
        * @param id The unique identifier of the HTLC payment.
        * @param amount The amount of the payment.
        * @param deadline The timestamp (in seconds since 1970) of when the HTLC expires.
        * @param usingSecret The secret used to unlock the payment.
        * @param opaque The optional opaque data provided when creating the lock.
        * @param cancelled True if the payment is cancelled, false if it is paid.
     */
    event HTLCPaymentRemoved(bytes32 indexed id, uint256 amount, uint256 deadline, string usingSecret, string opaque, bool cancelled);

}

/**
    * @title IHTLCPayment interface for HTLC payments
    * @notice The HTLC payment service is used to manage the HTLC payments for an account.
    <br>It is implement by a facet to manage the HTLC payments for accounts.
    * @dev This interface is used to manage the HTLC payments for an account. 
    <br>It is used to create, verify HTLC payments.
    <br>There is no function to accept or cancel a payment in this interface as this is the role of the user of the facet to implement the logic.
    <br>Inherit from [IHTLCPaymentInternal](./api-IHTLCPaymentInternal) to access the events.
    <br>It is used by the functions `lockFunds` and `unlockFunds` of the [ISoCashAccountActions](./api-ISoCashAccountActions) implementation.
    <br>
        <br>The `HTLC` structure is defined as follow:<br>
| Field          | Description                                                                                                              |<nl>
|----------------|--------------------------------------------------------------------------------------------------------------------------|<nl>
| `recipient`      | The expected beneficiary of the locked funds                                                                             |<nl>
| `amount`         | The amount locked for the payment                                                                                        |<nl>
| `deadline`       | The timestamp in sec (same as block.timestamp) when the lock expires                                                     |<nl>
| `hashlockPaid`   | The hash of the secret that locks the payment                                                                            |<nl>
| `hashlockCancel` | The hash of the secret that can cancel the payment (optional - and not to be used)                                         |<nl>
| `opaque`         | An optional opaque data to be interpreted by the user according to their protocol (a JSON string is recommended)           |<nl>
| `state`          | The state of the HTLC and can be `INITIATED=0`, `PAID=1` or `CANCELLED=2`                                                 |<nl>
     */
interface IHTLCPayment is IHTLCPaymentInternal {

    /**
        * @notice get the HTLC payment structure for an id.
        * @dev This function is used to get the HTLC payment structure for an id.
        * @param id The unique identifier of the HTLC payment.
        * @return The HTLC structure as defined above.
     */
    function getHTLCPayment(bytes32 id) external view returns (HTLC memory);

    /**
        * @notice Verify the secret of a HTLC payment.
        * @dev This function is used to verify the secret of a HTLC payment.
        * @param id The unique identifier of the HTLC payment.
        * @param secret The secret to verify.
        * @return ok True if the secret is correct, false otherwise.
        * @return reason The reason why the verification failed: status is not `INITIATED`, deadline is reached, secret does not match the hash.
     */
    function verifyHTLC(
        bytes32 id,
        string calldata secret
    ) external view returns (bool ok, string memory reason);

    /**
        * @notice Verify the possibility to cancel a HTLC payment.
        * @dev This function is used to verify the possibility to cancel a HTLC payment.
        * @param id The unique identifier of the HTLC payment.
        * @param secret The secret to cancel (discouraged).
        * @return ok True if the secret is correct, false otherwise.
        * @return reason The reason why the verification failed: status is not `INITIATED`, deadline is not reached, secret does not match the cancel hash.
     */
    function verifyHTLCCancel(
        bytes32 id,
        string calldata secret
    ) external view returns (bool ok, string memory reason);
}