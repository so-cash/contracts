// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

import {IFacet2} from "./IFacet2.sol";
import {Facet2Internal} from "./Facet2Internal.sol";


contract Facet2 is Facet2Internal, IFacet2 {
    function inc() external override {
        int v = _getValue();
        _setValue(v + 1);
    }

    function getVal() external view override returns (int) {
        return _getValue();
    }

    function setText(string calldata text) external override {
        _setText(text);
    }

    function getText() external view override returns (string memory) {
        return _getText();
    }
}