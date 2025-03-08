// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {IDiamondBase, DiamondBase} from "@fever-tokens/diamond/src/proxy/diamond/base/DiamondBase.sol";
import {IDiamondWritable, DiamondWritableInternal} from "@fever-tokens/diamond/src/proxy/diamond/writable/DiamondWritable.sol";
import {FacetCut} from "@fever-tokens/diamond/src/proxy/diamond/writable/IDiamondWritableInternal.sol";
import {DiamondReadable} from "@fever-tokens/diamond/src/proxy/diamond/readable/DiamondReadable.sol";
import {InitializableInternal} from "@fever-tokens/diamond/src/initializable/InitializableInternal.sol";
import {DiamondReadableFaceCut, DiamondWritableFaceCut} from "@fever-tokens/diamond/src/proxy/Proxy.sol";

import {AccountDataStorage} from "./facets/account-data/AccountDataStorage.sol";
import {OwnableStorage} from "@fever-tokens/diamond/src/ownable/OwnableStorage.sol";
import {ReentrancyGuardStorage} from "@fever-tokens/diamond/src/security/ReentrancyGuardStorage.sol";

// these imports are required to ensure compiler optimization does not ignore these contracts
// import {OwnableInternal} from "@fever-tokens/diamond/src/ownable/OwnableInternal.sol";
import {WhitelistedSendersInternal} from "./facets/whitelisted-senders/WhitelistedSendersInternal.sol";
// import {ERC20Base} from "@fever-tokens/diamond/src/token/ERC20/base/ERC20Base.sol";
// import {ReentrancyGuard} from "@fever-tokens/diamond/src/security/ReentrancyGuard.sol";

contract SoCashAccountDiamond is IDiamondBase, DiamondBase, DiamondWritableInternal {
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

contract SoCashAccountDiamondReadable is DiamondReadable {
}

contract SoCashAccountDiamondWritable is InitializableInternal, DiamondWritableInternal, WhitelistedSendersInternal {
    function initialize(string memory name) external initializer {
      ReentrancyGuardStorage.__init();
      OwnableStorage.__init(msg.sender);
      AccountDataStorage.__init(name);
    }

    function diamondCut(
        FacetCut[] calldata facetCuts,
        address target,
        bytes calldata data
    ) external onlyWhitelisted { // TODO: add user access control with a modifier
        _diamondCut(facetCuts, target, data);
    }
}