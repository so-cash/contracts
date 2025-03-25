// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {I_IBANService} from "./I_IBANService.sol";
import "./so-cash-referential.sol";


/**
    * @title ISoCashGlobalReferentialFull interface for the entry point of the global referential service
    * @notice The global referential service is used to find and manage the global referential of the so|cash scope.
    * @dev This interface inherits from [ISoCashGlobalReferential](./api-ISoCashGlobalReferential) and [I_IBANService](./api-I_IBANService).
    <br>It is used to access the global referential and to create and decode IBANs.
 */
interface ISoCashGlobalReferentialFull is ISoCashGlobalReferential, I_IBANService {
}


/**
    * @title ISoCashCountryReferentialFull interface for each country referential service
    * @notice The country referential service is used to find and manage the referential of a country in the so|cash scope.
    * @dev This interface inherits from [ISoCashCountryReferential](./api-ISoCashCountryReferential) and [I_IBANService](./api-I_IBANService).
    <br>It is used to access the country referential and to create and decode IBANs.
 */
interface ISoCashCountryReferentialFull is ISoCashCountryReferential, I_IBANService {
}