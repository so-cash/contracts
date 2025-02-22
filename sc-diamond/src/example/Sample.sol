// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IDiamondBase, DiamondBase} from "../proxy/diamond/base/DiamondBase.sol";
import {IDiamondReadable} from "../proxy/diamond/readable/DiamondReadable.sol";
import {IDiamondWritable, DiamondWritableInternal} from "../proxy/diamond/writable/DiamondWritable.sol";
import {FacetCut} from "../proxy/diamond/writable/IDiamondWritableInternal.sol";
import {DiamondReadable} from "../proxy/diamond/readable/DiamondReadable.sol";
import {InitializableInternal} from "../initializable/InitializableInternal.sol";

import {DiamondReadableFaceCut, DiamondWritableFaceCut} from "../proxy/Proxy.sol";

import {Facet1Storage} from "./facet1/Facet1Storage.sol";
import {Facet2Storage} from "./facet2/Facet2Storage.sol";

contract SampleDiamond is IDiamondBase, DiamondBase, DiamondWritableInternal {
    constructor(
        address _diamondReadablePackage,
        address _diamondWritablePackage,
        // the initialize() function selector followed by all its data. It will be transmitted as-is to the DiamondWritableInternal._initialize() function
        bytes memory _initData
    ) {
        // diamond cut
        FacetCut[] memory facetCuts = new FacetCut[](2);

        // // register DiamondReadable
        // bytes4[] memory diamondReadableSelectors = new bytes4[](4);
        // diamondReadableSelectors[0] = IDiamondReadable.facets.selector;
        // diamondReadableSelectors[1] = IDiamondReadable
        //     .facetFunctionSelectors
        //     .selector;
        // diamondReadableSelectors[2] = IDiamondReadable.facetAddresses.selector;
        // diamondReadableSelectors[3] = IDiamondReadable.facetAddress.selector;

        // // register DiamondWritable
        // bytes4[] memory diamondWritableSelectors = new bytes4[](1);
        // diamondWritableSelectors[0] = IDiamondWritable.diamondCut.selector;

        // facetCuts[0] = FacetCut({
        //     target: _diamondReadablePackage,
        //     action: FacetCutAction.ADD,
        //     selectors: diamondReadableSelectors
        // });

        // facetCuts[1] = FacetCut({
        //     target: _diamondWritablePackage,
        //     action: FacetCutAction.ADD,
        //     selectors: diamondWritableSelectors
        // });

        facetCuts[0] = DiamondReadableFaceCut.cuts(_diamondReadablePackage);
        facetCuts[1] = DiamondWritableFaceCut.cuts(_diamondWritablePackage);
        _diamondCut(facetCuts, _diamondWritablePackage, _initData);
    }

    receive() external payable {}
}

contract SampleDiamondReadable is DiamondReadable {
}

contract SampleDiamondWritable is InitializableInternal, DiamondWritableInternal {
    function initialize(uint256 firstValue, string calldata firstText) external initializer {
        // initialize the DiamondWritableInternal contract
        Facet1Storage.__init(firstValue);
        Facet2Storage.__init(firstText);
    }

    function diamondCut(
        FacetCut[] calldata facetCuts,
        address target,
        bytes calldata data
    ) external {
        _diamondCut(facetCuts, target, data);
    }
}