// SPDX-License-Identifier: MIT
// FeverTokens Contracts v1.0.0

pragma solidity ^0.8.17;

import {IFacet2V2} from "./IFacet2-v2.sol";
import {Facet2Internal} from "./Facet2Internal.sol";
// contract used to test the upgrade of a Facet2
// it removes the inc() and adds the increment() function
contract Facet2V2 is Facet2Internal, IFacet2V2 {
    function increment() external {
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