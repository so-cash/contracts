// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;


type CountryCode is bytes2;

/**
    * @title I_IBANService interface for international bank account number (IBAN) service
    * @notice Create and decode IBANs that are managed within the so|cash scope.
    * @dev This interface is used to create and decode IBANs. It is implemented by any service capable of creating or decoding IBANs, even on a partial scope. <br>Consult the documentation of the provider for more information. 
    <br>Typical implementation are done by the so|cash referential, global and by country.
    <br>The general structure for coding and decoding IBANs is a country code (ISO-3166 2 letters codes) and a set of codes that are specific to the country.
    <br>For example, the IBAN for a French bank account is FR1420041010050500013M02606.
    <br>It is composed of FR (country code), 20041 (bank code), 01005 (branch code), 0500013M026 (account number), the last 3 are the codes.
 */
interface I_IBANService {
    /**
     * @notice Create an IBAN from a country code and a set of codes.
     * @dev The function should return a valid IBAN if the country code and the codes are valid else it can fail.
     * @param country The country code of the IBAN to create. It must be 2 letters long.
     * @param codes Array of codes of the IBAN to create accouding to the country standard. They must be valid for the country.
     * @return The IBAN created from the country code and the codes.
     */
    function createIBAN(CountryCode country, string[] memory codes) external view returns (string memory);

    /**
        * @notice Decode an IBAN to a country code and a set of codes.
        * @dev The function should return the country code and the codes if the IBAN is valid. The function should never fail.
        <br>If the country code or the bank code cannot be resolved then the valid flag should be false.
        * @param iban The IBAN to decode.
        * @return valid True if the IBAN is valid, false otherwise.
        * @return country The country code of the IBAN.
        * @return codes Array of codes of the IBAN according to the country standard.
        */
    function decodeIBAN(string memory iban) external view returns (bool valid, CountryCode country, string[] memory codes);
    
    /**
        * @notice Decode an IBAN to a bank module and an account smart contract address.
        * @dev The function should return the bank module and the account if the IBAN is valid. The function should never fail.
        <br>If the bank or the account cannot be resolved then the valid flag should be false and the addresses are zeroed.
        * @param iban The IBAN to decode.
        * @return valid True if the IBAN is valid, false otherwise.
        * @return bank The bank address of the IBAN. Typically a [ISoCashBank](./api-ISoCashBank) contract or zero if the bank cannot be resolved.
        * @return account The account address of the IBAN. Typically a [ISoCashAccount](./api-ISoCashAccount) contract or zero if the account cannot be resolved.
        */
    function decodeIBANToContracts(string memory iban) external view returns (bool valid, address bank, address account);
}