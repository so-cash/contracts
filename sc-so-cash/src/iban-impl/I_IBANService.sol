// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

type CountryCode is bytes2;


interface I_IBANService {
    function createIBAN(CountryCode country, string[] memory codes) external view returns (string memory);
    function decodeIBAN(string memory iban) external view returns (bool valid, CountryCode country, string[] memory codes);
}