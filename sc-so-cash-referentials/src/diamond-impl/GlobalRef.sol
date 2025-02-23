// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {IDiamondBase, DiamondBase} from "@fever-tokens/diamond/src/proxy/diamond/base/DiamondBase.sol";
import {IDiamondWritable, DiamondWritableInternal} from "@fever-tokens/diamond/src/proxy/diamond/writable/DiamondWritable.sol";
import {FacetCut} from "@fever-tokens/diamond/src/proxy/diamond/writable/IDiamondWritableInternal.sol";
import {DiamondReadable} from "@fever-tokens/diamond/src/proxy/diamond/readable/DiamondReadable.sol";
import {InitializableInternal} from "@fever-tokens/diamond/src/initializable/InitializableInternal.sol";
import {DiamondReadableFaceCut, DiamondWritableFaceCut} from "@fever-tokens/diamond/src/proxy/Proxy.sol";

import {ISoCashGlobalReferential} from "../intf/so-cash-referential.sol";

contract GlobalReferentialDiamond is IDiamondBase, DiamondBase, DiamondWritableInternal {
    constructor(
        address _diamondReadablePackage,
        address _diamondWritablePackage,
        // the initialize() function selector followed by all its data. It will be transmitted as-is to the DiamondWritableInternal._initialize() function
        bytes memory _initData
    ) {
        // diamond cut
        FacetCut[] memory facetCuts = new FacetCut[](2);

        facetCuts[0] = DiamondReadableFaceCut.cuts(_diamondReadablePackage);
        facetCuts[1] = DiamondWritableFaceCut.cuts(_diamondWritablePackage);
        _diamondCut(facetCuts, _diamondWritablePackage, _initData);
    }

    receive() external payable {}
}

contract GlobalReferentialDiamondReadable is DiamondReadable {
}

contract GlobalReferentialDiamondWritable is InitializableInternal, DiamondWritableInternal {
    function initialize() external initializer {
    }

    function diamondCut(
        FacetCut[] calldata facetCuts,
        address target,
        bytes calldata data
    ) external { // TODO: add user access control with a modifier
        _diamondCut(facetCuts, target, data);
    }
}