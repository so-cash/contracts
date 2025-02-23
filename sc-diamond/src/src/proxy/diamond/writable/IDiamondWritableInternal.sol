// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

enum FacetCutAction {
    ADD,
    REPLACE,
    REMOVE
}

struct FacetCut {
    address target;
    FacetCutAction action;
    bytes4[] selectors;
}

interface IDiamondWritableInternal {

    event DiamondCut(FacetCut[] facetCuts, address target, bytes data);

    error DiamondWritable__InvalidInitializationParameters();
    error DiamondWritable__RemoveTargetNotZeroAddress();
    error DiamondWritable__ReplaceTargetIsIdentical();
    error DiamondWritable__SelectorAlreadyAdded();
    error DiamondWritable__SelectorIsImmutable();
    error DiamondWritable__SelectorNotFound();
    error DiamondWritable__SelectorNotSpecified();
    error DiamondWritable__TargetHasNoCode();

}
