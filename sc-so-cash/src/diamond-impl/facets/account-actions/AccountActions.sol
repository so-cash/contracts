// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {ISoCashAccountActions} from "../../../intf/so-cash-account.sol";
import {
  RecipentInfo, 
  BIC, IBAN,
  ISoCashAccount} from "../../../intf/so-cash-types.sol";

import {ERC20BaseInternal} from "@fever-tokens/diamond/src/token/ERC20/base/ERC20BaseInternal.sol";
import {IERC20Base} from "@fever-tokens/diamond/src/token/ERC20/base/IERC20Base.sol";
import {AccountDataInternal} from "../account-data/AccountDataInternal.sol";
import {HTLCPaymentInternal, HTLC, HTLCState} from "../htlc-payment/HTLCPaymentInternal.sol";
import {WhitelistedSendersInternal} from "../whitelisted-senders/WhitelistedSendersInternal.sol";

contract AccountActions is ISoCashAccountActions, IERC20Base, ERC20BaseInternal, AccountDataInternal, HTLCPaymentInternal, WhitelistedSendersInternal {
  
  /** ERC20 Base Implementation */
  function totalSupply() external override view returns (uint256) {
    return _bank().balanceOf(address(this));
  }
  function balanceOf(address) external override view returns (uint256) {
    return _bank().balanceOf(address(this));
  }
  function allowance(address holder, address spender) external override view returns (uint256) {
    return _allowance(holder, spender);
  }
  function approve(address spender, uint256 amount) external override onlyWhitelisted returns (bool) {
    return _approve(address(this), spender, amount);
  }
  function transfer( address recipient, uint256 amount ) external override onlyWhitelisted returns (bool) {
    return _bank().transfer(RecipentInfo(ISoCashAccount(recipient), BIC.wrap(0), IBAN.wrap(0)), amount, "ERC20 Transfer");
  }
  function transferFrom( address, address recipient, uint256 amount) external override returns (bool) {
    return _transferUsingAllowance(msg.sender, RecipentInfo(ISoCashAccount(recipient), BIC.wrap(0), IBAN.wrap(0)), amount, "ERC20 TransferFrom");
  }
  function increaseAllowance(  address spender,  uint256 addedValue) external override onlyWhitelisted returns (bool) {
    address holder = address(this);
    uint256 currentAllowance = _allowance(holder, spender);
    if (currentAllowance != type(uint256).max) {
        unchecked {
            _approve(holder, spender, currentAllowance + addedValue);
        }
    }
    return true;
  }
  function decreaseAllowance(address spender,uint256 subtractedValue) external override onlyWhitelisted returns (bool) {
    address holder = address(this);
    uint256 allowed = _allowance(holder, spender);
    if (subtractedValue > allowed)
        revert("ERC20Base: Insufficient Allowance");
    unchecked {
        _approve(holder, spender, allowed - subtractedValue);
    }
    return true;
  }

  /** so|cash implementation */
  function balance() external view override returns(uint256) {
    return _bank().balanceOf(address(this));
  }
  function lockedBalance() external view override returns(uint256) {
    return _bank().lockedBalanceOf(ISoCashAccount(address(this)));
  }
  function unlockedBalance() external view override returns(uint256) {
    return _bank().unlockedBalanceOf(ISoCashAccount(address(this)));
  }
  function fullBalance() external view override returns(int256) {
    return _bank().fullBalanceOf(ISoCashAccount(address(this)));
  }

  function _transferUsingAllowance(address sender, RecipentInfo memory recipient, uint256 amount, string memory details) internal returns (bool) {
    uint256 currentAllowance = _allowance(address(this), sender);
    require(
        currentAllowance >= amount,
        "SoC: transfer amount exceeds allowance"
    );
    unchecked {
        _approve(address(this), sender, currentAllowance - amount);
    }
    // If we have locked the funds, we need to unlock them here
    return _bank().transfer(recipient, amount, details);
  }

  function transferEx(RecipentInfo calldata recipient, uint256 amount, string calldata details) external override returns (bool) {
    if (_isWhitelisted(msg.sender)) {
      return _bank().transfer(recipient, amount, details);
    } else {
      return _transferUsingAllowance(msg.sender, recipient, amount, details);
    }
  }


  function lockFunds(RecipentInfo calldata recipient, uint256 amount, 
              uint256 deadline, bytes32 hashlockPaid, bytes32 hashlockCancel, 
              string calldata opaque) external override onlyWhitelisted returns (bytes32 key) {
    key = saveHTLCPayment(
        recipient,
        amount,
        deadline,
        hashlockPaid,
        hashlockCancel,
        opaque,
        HTLCState.INITIATED
    );
    require(_bank().lockFunds(amount), "SoC: lockFunds failed");
    return key;
  }
  function transferLockedFunds(bytes32 key, RecipentInfo calldata , string calldata secret, string calldata details) external override returns (bool) {
    // can be called by anyone with the secret
    HTLC memory htlc = closeHTLCPayment(key, secret);
    require( _bank().unlockFunds(htlc.amount) , "SoC: unlockFunds failed");
    // Attention the recipient is the one from the htlc not the one passed in the parameters
    return _bank().transfer(htlc.recipient, htlc.amount, details);
  }
  function unlockFunds(bytes32 key, string calldata secret) external override onlyWhitelisted returns (bool) {
    HTLC memory htlc = cancelHTLCPayment(key, secret);
    return _bank().unlockFunds(htlc.amount);
  }
}