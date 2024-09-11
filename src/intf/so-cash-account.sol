// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../intf/whitelisted-senders.sol";
import "../intf/htlc-payment.sol";
import "../utilities/whitelisted-senders.sol";
import "./so-cash-types.sol";
interface ISoCashOwnedAccount is ISoCashAccount, IERC20Metadata {
  function bank() external view returns (ISoCashBank);

  function name() external view returns(string memory);
  function iban() external view returns(string memory);
  function accountNumber() external view returns(AccountNumber);

  function balance() external view returns(uint256);
  function lockedBalance() external view returns(uint256);
  function unlockedBalance() external view returns(uint256);
  function fullBalance() external view returns(int256);

  function getAttributeStr(bytes32 name) view external returns(string memory);
  function setAttributeStr(bytes32 name, string memory value) external;
  function getAttributeNum(bytes32 name) view external returns(int);
  function setAttributeNum(bytes32 name, int value) external;

  function transferEx(RecipentInfo calldata recipient, uint256 amount, string calldata details) external returns (bool);

  function lockFunds(RecipentInfo calldata recipient, uint256 amount, 
              uint256 deadline, bytes32 hashlockPaid, bytes32 hashlockCancel, 
              string calldata opaque) external returns (bytes32 key);
  function transferLockedFunds(bytes32 key, RecipentInfo calldata recipient, string calldata secret, string calldata details) external returns (bool);
  function unlockFunds(bytes32 key, string calldata secret) external returns (bool);
}

interface ISoCashAccountFull is ISoCashOwnedAccount, IHTLCPayment, IWhitelistedSenders, IOwnable {}