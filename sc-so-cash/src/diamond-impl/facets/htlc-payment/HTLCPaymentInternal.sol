// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {HTLC, HTLCState, IHTLCPaymentInternal, RecipentInfo} from "../../../intf/htlc-payment.sol";
import {HTLCPaymentStorage} from "./HTLCPaymentStorage.sol";


contract HTLCPaymentInternal is IHTLCPaymentInternal {

    function saveHTLCPayment(
        RecipentInfo memory recipient,
        uint256 amount,
        uint256 deadline,
        bytes32 hashlockPaid,
        bytes32 hashlockCancel,
        string calldata opaque,
        HTLCState state
    ) internal returns (bytes32 id) {
      // require(beneficiary != address(0), "HTLC: beneficiary cannot be zero address");
      require(amount > 0, "HTLC: amount cannot be zero");
      require(deadline >= block.timestamp, "HTLC: deadline cannot be in the past");
      HTLCPaymentStorage.Layout storage l = HTLCPaymentStorage.layout();
      id = keccak256(abi.encodePacked(msg.sender, amount, l._htlcCounter++, block.number)); // should we add more fields like the hashes or the block number?
      l._payments[id] = HTLC(recipient, amount, deadline, hashlockPaid, hashlockCancel, opaque, state);
      emit HTLCPaymentCreated(id, hashlockPaid, l._payments[id]);
      return id;
    }

    function _getHTLCPayment(bytes32 id) internal view returns (HTLC memory) {
      HTLCPaymentStorage.Layout storage l = HTLCPaymentStorage.layout();
      return l._payments[id];
    }

    function _verifyHTLC(
        bytes32 id,
        string calldata secret
    ) internal view returns (bool ok, string memory reason) {
      HTLCPaymentStorage.Layout storage l = HTLCPaymentStorage.layout();
        
      HTLC storage htlc = l._payments[id];
      // if(htlc.beneficiary == address(0)) return (false, "HTLC: invalid id or debt already cleared while closing");
      if(htlc.hashlockPaid == 0) return (false, "HTLC: invalid id or debt already cleared while closing");
      if(htlc.deadline < block.timestamp) return (false, "HTLC: deadline expired");
      if(htlc.hashlockPaid != sha256(abi.encodePacked(secret))) return (false, "HTLC: secret mismatch");
      return (true, "");
    }

    function _verifyHTLCCancel(
        bytes32 id,
        string calldata secret
    ) internal view returns (bool ok, string memory reason) {
      HTLCPaymentStorage.Layout storage l = HTLCPaymentStorage.layout();
      
      HTLC storage htlc = l._payments[id];
      if(htlc.hashlockPaid == 0) return (false, "HTLC: invalid id or debt already cleared");
      bool expired = htlc.deadline <= block.timestamp;
      bool matchCancelHash = htlc.hashlockCancel == sha256(abi.encodePacked(secret));
      if( !expired && !matchCancelHash ) return(false, "HTLC: deadline not yet expired or invalid cancel secret");
      return (true, "");
    }

    function closeHTLCPayment(bytes32 id, string calldata secret) internal returns (HTLC memory htlc){
    
      // first check the id exists 
      (bool ok, string memory reason) = _verifyHTLC(id, secret);
      require(ok, reason); // fail here if not allowed
      HTLCPaymentStorage.Layout storage l = HTLCPaymentStorage.layout();
      htlc = l._payments[id];
      delete l._payments[id];
      emit HTLCPaymentRemoved(id, htlc.amount, htlc.deadline, secret, htlc.opaque, false);
      return htlc;
    }

    function cancelHTLCPayment(bytes32 id, string calldata secret) internal returns (HTLC memory htlc){
      // first check the id exists 
      (bool ok, string memory reason) = _verifyHTLCCancel(id, secret);
      require(ok, reason); // fail here if not allowed
      HTLCPaymentStorage.Layout storage l = HTLCPaymentStorage.layout();
      htlc = l._payments[id];
      delete l._payments[id];
      emit HTLCPaymentRemoved(id, htlc.amount, htlc.deadline, secret, htlc.opaque, true);
      return htlc;
    }
}