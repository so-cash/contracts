// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {AddressUtils} from "../utils/AddressUtils.sol";
import {IProxy} from "./IProxy.sol";
import {IDiamondReadable} from "./diamond/readable/IDiamondReadable.sol";
import {FacetCut, FacetCutAction} from "./diamond/writable/IDiamondWritableInternal.sol";
import {IDiamondWritable} from "./diamond/writable/IDiamondWritable.sol";

/**
 * @title Base proxy contract
 */
abstract contract Proxy is IProxy {
    using AddressUtils for address;

    /**
     * @notice delegate all calls to implementation contract
     * @dev reverts if implementation address contains no code, for compatibility with metamorphic contracts
     * @dev memory location in use by assembly may be unsafe in other contexts
     */
    fallback() external payable virtual {
        address implementation = _getImplementation();

        if (!implementation.isContract())
            revert("Proxy: Implementation Is Not Contract");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(
                gas(),
                implementation,
                0,
                calldatasize(),
                0,
                0
            )
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @notice get logic implementation address
     * @return implementation address
     */
    function _getImplementation() internal virtual returns (address);
}


library DiamondReadableFaceCut {
    function cuts(address target) internal pure returns (FacetCut memory) {
        bytes4[] memory result = new bytes4[](4);
        result[0] = IDiamondReadable.facets.selector;
        result[1] = IDiamondReadable.facetFunctionSelectors.selector;
        result[2] = IDiamondReadable.facetAddresses.selector;
        result[3] = IDiamondReadable.facetAddress.selector;
        return FacetCut({
            target: target,
            action: FacetCutAction.ADD,
            selectors: result
        });
    }
}
library DiamondWritableFaceCut {
    function cuts(address target) internal pure returns (FacetCut memory) {
        bytes4[] memory result = new bytes4[](1);
        result[0] = IDiamondWritable.diamondCut.selector;
        return FacetCut({
            target: target,
            action: FacetCutAction.ADD,
            selectors: result
        });
    }
}