// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {
  ISoCashBank,
  ISoCashAccount,
  ISoCashBankExternal
  } from "@so-cash/sc-so-cash/src/intf/so-cash-bank.sol";
import {I_IBANService, CountryCode} from "../../../intf/I_IBANService.sol";
import {CountryManagerInternal} from "../../CountryManagerInternal.sol";
import {Generic_IBANServiceInternal, LocalIBANCalculator} from "./GenericIBANService.sol";

contract Router_IBANServiceFacet is I_IBANService, CountryManagerInternal, Generic_IBANServiceInternal {

  function _defaultDecodeIBAN(string memory iban) internal pure returns (bool, CountryCode , string[] memory ) {
    (bool valid, , string memory bankCode5, string memory branchCode5, string memory accountNumber11, ) 
        = LocalIBANCalculator.extractFrenchIBAN(iban);
    CountryCode country = _extractCountryCode(iban);
    string[] memory codes = new string[](3);
    codes[0] = bankCode5;
    codes[1] = branchCode5;
    codes[2] = accountNumber11;
    return (valid, country, codes);
  }

  function createIBAN(CountryCode country, string[] memory codes) external view returns (string memory) {
    require(codes.length == 3, "IBANServiceFacet: invalid codes length");
    address c = address(_getCountry(CountryCode.unwrap(country)));
    if (c == address(0)) {
        return LocalIBANCalculator.calculateFrenchIBAN(string(abi.encodePacked(country)),codes[0], codes[1], codes[2]);
    } else {
        return I_IBANService(c).createIBAN(country, codes);
    }
  }

  function decodeIBAN(string memory iban) external view returns (bool, CountryCode , string[] memory ) {
    CountryCode country = _extractCountryCode(iban);
    address c = address(_getCountry(CountryCode.unwrap(country)));
    if (c == address(0)) {
        return _defaultDecodeIBAN(iban);
    } else {
        return I_IBANService(c).decodeIBAN(iban);
    }
  }

  function decodeIBANToContracts(string memory iban) external view returns (bool valid, address bank, address account) {
    CountryCode country = _extractCountryCode(iban);
    address c = address(_getCountry(CountryCode.unwrap(country)));
    require(c != address(0), "IBANServiceFacet: country not found"); 
    return I_IBANService(c).decodeIBANToContracts(iban);
  }
}


