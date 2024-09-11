// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract IBANCalculator {
    function calculateIBAN(string memory countryCode, string memory bban) public pure returns (string memory) {
        string memory fakeIban = string(abi.encodePacked(bban, countryCode, "00"));
        uint256 fakeIbanValue = ibanStringToNumber(fakeIban);
        uint16 key = ibanKey(fakeIbanValue);
        string memory key2 = padWithZeros( uintToString(key), 2);
        return string(abi.encodePacked(countryCode, key2, bban));
    }

    function frenchRIBKey(uint256 bankCode, uint256 branchCode, uint256 accountNumber) public pure returns (uint16) {
        uint256 key = (89 * bankCode + 15 * branchCode + 3 * accountNumber);
        key = 97 - key % 97;
        return uint16(key);
    } 

    function ibanKey(uint256 fakeIbanValue) public pure returns (uint16) {
        uint256 key = 98 - fakeIbanValue % 97;
        return uint16(key);
    }

    function ibanStringToNumber(string memory s) public pure returns (uint256) {
        uint256 result = 0;
        for (uint i = 0; i < bytes(s).length; i++) {
            uint8 c = uint8(bytes(s)[i]);
            if (c >= 48 ) {
                unchecked {
                    c = uint8(bytes(s)[i]) - 48;
                }
            } else {
                c = 255;
            }
            if (c >=0 && c <= 9) {
                result = result * 10 + c;
            } else {
                unchecked {
                    if (c >= 97-48 && c <= 122-48) { // a-z (lowercase letters)
                        c -= 97-65; // make uppercase
                    }
                    // now convert letter to number
                    if (c >= 17 && c <= 42) { // A-Z
                        c = (c - 17) +10; // A=10, B=11, ... Z=35
                    } else {
                        c = 0; // invalid character ignored
                    }
                    if (c>0) result = result * 100 + c;
                }
            }
        }
        return result;
    }

    function frenchStringToNumber(string memory s) public pure returns (uint256) {
        uint256 result = 0;
        for (uint i = 0; i < bytes(s).length; i++) {
            uint8 c = uint8(bytes(s)[i]);
            if (c >= 48 ) {
                unchecked {
                    c = uint8(bytes(s)[i]) - 48;
                }
            } else {
                c = 255;
            }
            if (c >=0 && c <= 9) {
                result = result * 10 + c;
            } else {
                unchecked {
                    if (c >= 97-48 && c <= 122-48) { // a-z (lowercase letters)
                        c -= 97-65; // make uppercase
                    }
                    // now convert letter to number
                    if (c >= 17 && c <= 34) { // A-R
                        c = (c - 17) % 9 +1; // A=1, B=2, ... R=9
                    } else if (c >= 35 && c <= 42) { // S-Z
                        c = (c - 16) % 9 +1; // S=2, T=3, ... Z=9
                    } else {
                        c = 0; // invalid character ignored
                    }
                    if (c>0) result = result * 10 + c;
                }
            }
        }
        return result;
    }

    function padWithZeros(string memory s, uint8 length) public pure returns (string memory) {
        if (bytes(s).length >= length) {
            return s;
        }
        unchecked {
            length = length - uint8(bytes(s).length);
        }
        bytes memory zeroBytes = new bytes(length );
        for(uint i = 0; i < length; i++){
            zeroBytes[i] = bytes1(uint8(48)); // ASCII value of "0"
        }
        return string(abi.encodePacked(zeroBytes, s));
    }
    function uintToString(uint v) public pure returns (string memory str) {
        if (v == 0) {
            return "0";
        }
        uint maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint i = 0;
        while (v != 0) {
            uint remainder = v % 10;
            v = v / 10;
            reversed[i++] = bytes1(uint8(48 + remainder));
        }
        bytes memory s = new bytes(i);
        for (uint j = 0; j < i; j++) {
            s[j] = reversed[i - 1 - j];
        }
        str = string(s);
    }

    function frenchBBAN(string memory bankCode5, string memory branchCode5, string memory accountNumber11) public pure returns (string memory) {
        uint16 key = frenchRIBKey(
            frenchStringToNumber(bankCode5), 
            frenchStringToNumber(branchCode5), 
            frenchStringToNumber(accountNumber11));
        bankCode5 = padWithZeros(bankCode5, 5);
        branchCode5 = padWithZeros(branchCode5, 5);
        accountNumber11 = padWithZeros(accountNumber11, 11);
        string memory key2 = padWithZeros( uintToString(key), 2);
        return string(abi.encodePacked(bankCode5, branchCode5, accountNumber11, key2));
    }

    /** This is the function to be used for so|cash
    * bankCode will be a 5 digit string defined in the constructor of the CommercialBankCash contract
    * branchCode will be a 5 digit string defined in the constructor of the CommercialBankCash contract
    * accountNumber will be a 11 digit string defined when the account is attached to the CommercialBankCash contract
     */
    function calculateFrenchIBAN(string memory bankCode5, string memory branchCode5, string memory accountNumber11) public pure returns (string memory) {
        string memory bban = frenchBBAN(bankCode5, branchCode5, accountNumber11);
        return calculateIBAN("FR", bban);
    }

    // function trimTrailingZeroBytes(string memory input) public pure returns (string memory) {
    //     bytes memory inputBytes = bytes(input);
    //     uint256 length = inputBytes.length;
    //     while (length > 0 && inputBytes[length - 1] == 0x00) {
    //         length--;
    //     }
    //     bytes memory trimmedBytes = new bytes(length);
    //     for (uint256 i = 0; i < length; i++) {
    //         trimmedBytes[i] = inputBytes[i];
    //     }
    //     return string(trimmedBytes);
    // }

    function extractFrenchIBAN(string memory iban) public pure returns (bool valid, string memory bankCode5, string memory branchCode5, string memory accountNumber11, uint16 ribKey) {
        bytes memory b = bytes(iban);
        // check french prefix
        if (b[0] != bytes1(uint8(0x46)) || b[1] != bytes1(uint8(0x52))) { // FR
            return (false, "", "", "", 0);
        }
        // check length (e.g. FR29200410100500013M0260005)
        if (b.length < 27) { // 2 + 2 + 5 + 5 + 11 + 2 = 27 . If more the data will be ignored
            return (false, "", "", "", 0);
        }
        if (b.length > 27) { // ensure we only have zeroes here after the max size
            for (uint256 index = 27; index < b.length; index++) {
                if (b[index] != bytes1(0x00)) {
                    return (false, "", "", "", 0);
                }
            }
        }

        // extract fields
        uint256 _ibanKey = ibanStringToNumber(string(abi.encodePacked(b[2], b[3])));
        ribKey = uint16(frenchStringToNumber(string(abi.encodePacked(b[25], b[26]))));
        bankCode5 = string(abi.encodePacked(b[4], b[5], b[6], b[7], b[8]));
        branchCode5 = string(abi.encodePacked(b[9], b[10], b[11], b[12], b[13]));
        accountNumber11 = string(abi.encodePacked(b[14], b[15], b[16], b[17], b[18], b[19], b[20], b[21], b[22], b[23], b[24]));

        // check ribKey
        uint16 checkRibkey = frenchRIBKey(
            frenchStringToNumber(bankCode5), 
            frenchStringToNumber(branchCode5), 
            frenchStringToNumber(accountNumber11));
        if (checkRibkey != ribKey) {
            return (false, bankCode5, branchCode5, accountNumber11, ribKey);
        }
        // check ibanKey
        string memory fakeIban = string(abi.encodePacked(bankCode5, branchCode5, accountNumber11, b[25], b[26], "FR00"));
        uint256 fakeIbanValue = ibanStringToNumber(fakeIban);
        uint16 checkIbanKey = ibanKey(fakeIbanValue);
        if (checkIbanKey != _ibanKey) {
            return (false, bankCode5, branchCode5, accountNumber11, ribKey);
        }
        return (true, bankCode5, branchCode5, accountNumber11, ribKey);
    }
}
