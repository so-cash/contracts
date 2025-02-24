// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {HTLC, IHTLCPayment} from "../../../intf/htlc-payment.sol";
import {HTLCPaymentInternal} from "./HTLCPaymentInternal.sol";

contract HTLCPayment is HTLCPaymentInternal, IHTLCPayment {
  function getHTLCPayment(bytes32 id ) external view override returns (HTLC memory) {
    return _getHTLCPayment(id);
  }
  function verifyHTLC(
        bytes32 id,
        string calldata secret
    ) external view override returns (bool ok, string memory reason) {
    return _verifyHTLC(id, secret);
  }
  function verifyHTLCCancel(
      bytes32 id,
      string calldata secret
  ) external view override returns (bool ok, string memory reason) {
    return _verifyHTLCCancel(id, secret);
  }
}