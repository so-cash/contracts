// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IFacet1} from "./facet1/IFacet1.sol";
import {IFacet2} from "./facet2/IFacet2.sol";

interface ISample is IFacet1, IFacet2 {
}