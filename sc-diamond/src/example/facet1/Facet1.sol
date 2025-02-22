// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

import {IFacet1} from "./IFacet1.sol";
import {Facet1Internal} from "./Facet1Internal.sol";


contract Facet1 is Facet1Internal, IFacet1 {
  function setValue(uint256 value) external override {
    _setValue(value);
  }

  function getValue() external view override returns (uint256) {
    return _getValue();
  }

  function setAddress(uint256 index, address account) external override {
    _setAddress(index, account);
  }

  function getAddress(uint256 index) external view override returns (address) {
    return _getAddress(index);
  }
}