// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../intf/htlc-payment.sol";

contract HTLCPaymentCapacity is IHTLCPayment{
      
    uint256 private _htlcCounter = 0; // to generate unique ids for the HTLCs
    mapping(bytes32 => HTLC) private _payments; // the HTLCs

    function saveHTLCPayment(
        RecipientInfo memory recipient,
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
        id = keccak256(abi.encodePacked(msg.sender, amount, _htlcCounter++, block.number)); // should we add more fields like the hashes or the block number?
        _payments[id] = HTLC(recipient, amount, deadline, hashlockPaid, hashlockCancel, opaque, state);
        emit HTLCPaymentCreated(id, hashlockPaid, _payments[id]);
        return id;
    }

    function getHTLCPayment(bytes32 id) public view returns (HTLC memory) {
        return _payments[id];
    }

    function verifyHTLC(
        bytes32 id,
        string calldata secret
    ) public view returns (bool ok, string memory reason) {
        HTLC storage htlc = _payments[id];
        // if(htlc.beneficiary == address(0)) return (false, "HTLC: invalid id or debt already cleared while closing");
        if(htlc.hashlockPaid == 0) return (false, "HTLC: invalid id or debt already cleared while closing");
        if(htlc.deadline < block.timestamp) return (false, "HTLC: deadline expired");
        if(htlc.hashlockPaid != sha256(abi.encodePacked(secret))) return (false, "HTLC: secret mismatch");
        return (true, "");
    }

    function verifyHTLCCancel(
        bytes32 id,
        string calldata secret
    ) public view returns (bool ok, string memory reason) {
        HTLC storage htlc = _payments[id];
        if(htlc.hashlockPaid == 0) return (false, "HTLC: invalid id or debt already cleared");
        bool expired = htlc.deadline <= block.timestamp;
        bool matchCancelHash = htlc.hashlockCancel == sha256(abi.encodePacked(secret));
        if( !expired && !matchCancelHash ) return(false, "HTLC: deadline not yet expired or invalid cancel secret");
        return (true, "");
    }

    function closeHTLCPayment(bytes32 id, string calldata secret) internal returns (HTLC memory htlc){
        // first check the id exists 
        (bool ok, string memory reason) = verifyHTLC(id, secret);
        require(ok, reason); // fail here if not allowed
        htlc = _payments[id];
        delete _payments[id];
        emit HTLCPaymentRemoved(id, htlc.amount, htlc.deadline, secret, htlc.opaque, false);
        return htlc;
    }

    function cancelHTLCPayment(bytes32 id, string calldata secret) internal returns (HTLC memory htlc){
        // first check the id exists 
        (bool ok, string memory reason) = verifyHTLCCancel(id, secret);
        require(ok, reason); // fail here if not allowed
        htlc = _payments[id];
        delete _payments[id];
        emit HTLCPaymentRemoved(id, htlc.amount, htlc.deadline, secret, htlc.opaque, true);
        return htlc;
    }
}
