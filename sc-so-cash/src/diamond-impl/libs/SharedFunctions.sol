// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

// import {IERC20Metadata} from "@fever-tokens/diamond/src/token/ERC20/extensions/IERC20Metadata.sol";
import "../../intf/so-cash-types.sol";
import "../../intf/so-cash-account.sol";
import "../../intf/so-cash-bank.sol";
import {
  ISoCashGlobalReferential, 
  ISoCashCountryReferential,
  BankIdentifier,
  CodeType
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
library SharedFunctions {
  function nothing() internal  {}
  // internal functions 
  function isContract(address _addr) internal view returns (bool) {
      uint32 size;
      assembly {
          size := extcodesize(_addr)
      }
      return (size > 0);
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

  function _ioa(ISoCashAccount account) internal pure returns (ISoCashOwnedAccount) {
    return ISoCashOwnedAccount(address(account));
  }
  function _iaw(ISoCashAccount account) internal pure returns (IWhitelistedSenders) {
    return IWhitelistedSenders(address(account));
  }
  function _ibi(ISoCashBank bank) internal pure returns (ISoCashInterBank) {
    return ISoCashInterBank(address(bank));
  }
  function _ibe(ISoCashBank bank) internal pure returns (ISoCashBankExternal) {
    return ISoCashBankExternal(address(bank));
  }
  function _ierc(ISoCashBank bank) internal pure returns (IERC20Compatibility) {
    return IERC20Compatibility(address(bank));
  }
  function notNullAccount(ISoCashAccount account) internal pure returns (bool) {
      return address(account) != address(0);
  }
  function notNullBank(ISoCashBank bank) internal pure returns (bool) {
      return address(bank) != address(0);
  }
  function notNullCountryRef(ISoCashCountryReferential country) internal pure returns (bool) {
      return address(country) != address(0);
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
  function _join(string memory a, string memory link, string memory b) internal pure returns(string memory) {
    if (bytes(a).length == 0) return b;
    else return string(abi.encodePacked(a, link, b));
  }

  function stringToBytes3(string memory str) internal pure returns (bytes3) {
    return bytes3(stringToBytes32(str));
  }
  function stringToBytes2(string memory str) internal pure returns (bytes2) {
    return bytes2(stringToBytes32(str));
  }    
  function stringToBytes10(string memory str) internal pure returns (bytes10) {
    return bytes10(stringToBytes32(str));
  }    
  function stringToBytes32(string memory str) public pure returns (bytes32 ) {
      return bytes32(bytes(str));
  }
  function bytes3ToString(bytes3 b) internal pure returns (string memory) {
    return string(abi.encodePacked(b));
  }
  function bytes2ToString(bytes2 b) internal pure returns (string memory) {
    return string(abi.encodePacked(b));
  }
}