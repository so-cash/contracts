// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {
  CodeType,
  ISoCashBankController} from "../intf/so-cash-referential.sol";
import {BankControllerInternal} from "./BankControllerInternal.sol";

contract BankController is BankControllerInternal, ISoCashBankController{

  function setBankController(CodeType bankCode, address controller) external {
    _setBankController(bankCode, controller);
  }

  function unsetBankController(CodeType bankCode, address controller) external {
    _unsetBankController(bankCode, controller);
  }

  function isBankController(CodeType bankCode, address controller) external view returns (bool) {
    return _isBankController(bankCode, controller);
  }
}