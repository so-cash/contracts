// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {
  ISoCashGlobalReferential, 
  BankIdentifier,
  CodeType
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {BIC, CCY} from "../../../intf/so-cash-types.sol";
import {ISoCashBankIdentity} from "../../../intf/so-cash-bank.sol";
import {BankIdentityInternal} from "./BankIdentityInternal.sol";

contract BankIdentity is ISoCashBankIdentity, BankIdentityInternal {
  function bic() external view override returns (string memory) {
    return string(abi.encodePacked(_bic()));
  }

  function codes() external view override returns (CodeType bankCode, CodeType branchCode) {
    BankIdentifier memory id = _bankIdentifier();
    return (id.codes[0], id.codes[1]);
  }

  function bankIdentifier() external view override returns (BankIdentifier memory) {
    return _bankIdentifier();
  }

  function country() external view returns (bytes2 ) {
    return _country();
  }

  function version() external view override returns (string memory) {
    return _version();
  }

  function currency() external view returns (CCY) {
    return _ccy();
  }
}