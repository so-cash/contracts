// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {
  CodeType,
  ISoCashBankControllerInternal} from "../intf/so-cash-referential.sol";
import {BankControllerStorage} from "./BankControllerStorage.sol";
import {OwnableInternal} from "@fever-tokens/diamond/src/ownable/OwnableInternal.sol";

contract BankControllerInternal is ISoCashBankControllerInternal, OwnableInternal {

  // TODO: protect this function with access control

  modifier onlyBankController(CodeType[] memory codes) {
    require(codes.length > 0, "At least one code is required");
    require( _owner() == msg.sender 
      || _isBankController(codes[0], msg.sender),
       "Only bank controller can call this function");
    _;
  }

  modifier onlyBankController1(CodeType bankCode) {
    require( _owner() == msg.sender 
      || _isBankController(bankCode, msg.sender),
       "Only bank controller can call this function");
    _;
  }


  function _setBankController(CodeType bankCode, address controller) internal {
    BankControllerStorage.Layout storage l = BankControllerStorage.layout();
    l.bankControllers[controller][bankCode] = true;
    emit BankControllerSet(bankCode, controller, true);
  }
  // TODO: protect this function with access control
  function _unsetBankController(CodeType bankCode, address controller) internal {
    BankControllerStorage.Layout storage l = BankControllerStorage.layout();
    l.bankControllers[controller][bankCode] = false;
    emit BankControllerSet(bankCode, controller, false);
  }
  function _isBankController(CodeType bankCode, address controller) internal view returns (bool) {
    BankControllerStorage.Layout storage l = BankControllerStorage.layout();
    return l.bankControllers[controller][bankCode];
  }
}