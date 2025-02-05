// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;


import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../intf/so-cash-types.sol";
import "../intf/so-cash-account.sol";
import "../intf/so-cash-bank.sol";

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
  function getBankOf(address _addr) external view returns (address) {
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
  function memcmp(bytes memory a, bytes memory b) internal pure returns(bool){
      return (a.length == b.length) && (keccak256(a) == keccak256(b));
  }
  function strcmp(string memory a, string memory b) internal pure returns(bool){
      return memcmp(bytes(a), bytes(b));
  }
  function sameCurrencyAndDecimals(IERC20Metadata a, IERC20Metadata b) external view returns(bool) {
      return strcmp(a.symbol(), b.symbol()) && (a.decimals() == b.decimals());
  }
  function _join(string memory a, string memory link, string memory b) external pure returns(string memory) {
    if (bytes(a).length == 0) return b;
    else return string(abi.encodePacked(a, link, b));
  }
}