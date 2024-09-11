// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../intf/so-cash-types.sol";

contract Controls {

    function notNullAccount(ISoCashAccount account) internal pure returns (bool) {
        return address(account) != address(0);
    }
    function notNullBank(ISoCashBank bank) internal pure returns (bool) {
        return address(bank) != address(0);
    }

    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function memcmp(bytes memory a, bytes memory b) internal pure returns(bool){
        return (a.length == b.length) && (keccak256(a) == keccak256(b));
    }
    function strcmp(string memory a, string memory b) internal pure returns(bool){
        return memcmp(bytes(a), bytes(b));
    }

    function sameCurrencyAndDecimals(IERC20Metadata a, IERC20Metadata b) internal view returns(bool) {
        return strcmp(a.symbol(), b.symbol()) && (a.decimals() == b.decimals());
    }

    function getBankOf(address _addr) internal view returns (address) {
        require(isContract(_addr), "CBC: The address is not a contract so it cannot be an account");
        address owner = Ownable(_addr).owner();
        if (isContract(owner)) {
            return owner;
        } else {
            return address(this); // assume that if the owner is not a smart contract it is a commercial bank
        }
    }

}