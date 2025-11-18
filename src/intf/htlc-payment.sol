// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./so-cash-types.sol";

interface IHTLCPayment {

    enum HTLCState {
        INITIATED,
        PAID,
        CANCELLED
    }

    struct HTLC {
      RecipientInfo recipient; // the expected beneficiary of the locked funds
      uint256 amount; // the amount to be repaid
      uint256 deadline; // the deadline to repay the debt in seconds
      bytes32 hashlockPaid; // the hashlock being the sha256 of the release secret
      bytes32 hashlockCancel; // the hashlock being the sha256 of the cancel secret (optional)
      string opaque; // optional opaque data to be interpreted by the user according to their protocol
      HTLCState state; // the state of the HTLC
    }

    event HTLCPaymentCreated(bytes32 indexed id, bytes32 indexed hashlockPaid, HTLC htlc);
    event HTLCPaymentRemoved(bytes32 indexed id, uint256 amount, uint256 deadline, string usingSecret, string opaque, bool cancelled);

    function getHTLCPayment(bytes32 id) external view returns (HTLC memory);
    function verifyHTLC(
        bytes32 id,
        string calldata secret
    ) external view returns (bool ok, string memory reason);
    function verifyHTLCCancel(
        bytes32 id,
        string calldata secret
    ) external view returns (bool ok, string memory reason);
}
