// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "../intf/so-cash-types.sol";
import "../intf/so-cash-bank.sol";
import "../intf/so-cash-account.sol";

import "../utilities/whitelisted-senders.sol";
import "../utilities/htlc-payments.sol";

contract SoCashAccount is ISoCashAccount, ISoCashOwnedAccount, WhitelistedSenders, HTLCPaymentCapacity {
  mapping(bytes32 => bytes) private _attributesStr;
  mapping(bytes32 => bytes32) private _attributesNum;
  mapping(address => uint256) private _allowances; // allowance of external address to transfer from this bank account only

  constructor(string memory name_) {
      _attributesStr[ACCOUNT_NAME] = bytes(name_);
  }
  // #################### PUBLIC FUNCTION IMPLEMENTATION ####################

  function name() public view returns (string memory) {
      return getAttributeStr(ACCOUNT_NAME);
  }

  function symbol() public view returns (string memory) {
      return IERC20Metadata(owner()).symbol();
  }

  function decimals() public view returns (uint8) {
      return IERC20Metadata(owner()).decimals();
  }

  function bank() public view override returns (ISoCashBank) {
    return ISoCashBank(owner());
  }

  function iban() public view override returns (string memory) {
    return _bank().ibanOf(this);
  }
  function accountNumber() public view override returns (AccountNumber) {
    return _bank().accountNumberOf(this);
  }

  function balance() public view override returns (uint256) {
    return _bank().balanceOf(address(this));
  }

  function fullBalance() public view override returns (int256) {
    return _bank().fullBalanceOf(this);
  }
  
  function balanceOf(address) public view override returns (uint256) {
    return _bank().balanceOf(address(this));
  }

  function totalSupply() public view returns (uint256) {
      return balance();
  }

  function lockedBalance() public view override returns (uint256) {
    return _bank().lockedBalanceOf(this);
  }
  function unlockedBalance() public view override returns (uint256) {
    return _bank().unlockedBalanceOf(this);
  }


  function getAttributeStr( bytes32 _name) public view returns (string memory) {
      bytes storage v = _attributesStr[_name];
      return string(v);
  }
  // TODO: Limit to only some used to set the attributes, client should not be allowed to do it
  function setAttributeStr(bytes32 _name, string memory value) public onlyWhitelisted {
      _attributesStr[_name] = bytes(value);
  }
  function getAttributeNum(bytes32 _name) public view returns (int) {
      bytes32 v = _attributesNum[_name];
      unchecked {
          return int(uint(v));
      }
  }
  // TODO: Limit to only some used to set the attributes, client should not be allowed to do it
  function setAttributeNum(bytes32 _name, int value) public onlyWhitelisted {
      _attributesNum[_name] = bytes32(uint(value));
  }

  function allowance(address , address spender) public view returns (uint256) {
    return _allowances[spender];
  }
  function approve(address spender, uint256 amount) public onlyWhitelisted returns (bool) {
    _approve(spender, amount);
    // TODO: Do we want to lock the funds here ?
    return true;
  }

  function transfer(address to, uint256 amount) public override onlyWhitelisted returns (bool) {
    return _bank().transfer(RecipientInfo(ISoCashAccount(to), BIC.wrap(0), IBAN.wrap(0)), amount, "ERC20 Transfer");
  }

  function transferEx(RecipientInfo calldata recipient, uint256 amount, string calldata details) public override returns (bool) {
    if (isWhitelisted(_msgSender())) {
      // allowed so transfer directly
      return _bank().transfer(recipient, amount, details);
    } else {
      // try to using an allowance
      return _transferUsingAllowance(_msgSender(), recipient, amount, details);
    }
  }

  function transferFrom(
      address, // actual sender will be the BankAccount
      address recipient,
      uint256 amount
  ) public override returns (bool) {
    return _transferUsingAllowance(_msgSender(), RecipientInfo(ISoCashAccount(recipient), BIC.wrap(0), IBAN.wrap(0)), amount, "ERC20 TransferFrom");
  }

  function _transferUsingAllowance(address sender, RecipientInfo memory recipient, uint256 amount, string memory details) internal returns (bool) {
    uint256 currentAllowance = _allowances[sender];
    require(
        currentAllowance >= amount,
        "SoC: transfer amount exceeds allowance"
    );
    unchecked {
        _approve(sender, currentAllowance - amount);
    }
    // If we have locked the funds, we need to unlock them here
    return _bank().transfer(recipient, amount, details);
  }

  function lockFunds(RecipientInfo calldata recipient, uint256 amount, 
              uint256 deadline, bytes32 hashlockPaid, bytes32 hashlockCancel, 
              string calldata opaque) public onlyWhitelisted returns (bytes32 key) {
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
  function transferLockedFunds(bytes32 key, RecipientInfo calldata recipient, string calldata secret, string calldata details) public returns (bool) {
    // can be called by anyone with the secret
    HTLC memory htlc = closeHTLCPayment(key, secret);
    require( _bank().unlockFunds(htlc.amount) , "SoC: unlockFunds failed");
    return _bank().transfer(recipient, htlc.amount, details);
  }
  function unlockFunds(bytes32 key, string calldata secret) public onlyWhitelisted returns (bool) {
    HTLC memory htlc = cancelHTLCPayment(key, secret);
    return _bank().unlockFunds(htlc.amount);
  }

  // #################### INTERNAL FUNCTION IMPLEMENTATION ####################
  function _bank() internal view returns (ISoCashBankExternal) {
    return ISoCashBankExternal(owner());
  }
  function _approve(address spender, uint256 amount) internal virtual {
      require(spender != address(0), "ERC20: approve to the zero address");

      _allowances[spender] = amount;
      emit Approval(address(this), spender, amount);
  }

  // #################### UTILITIES FUNCTIONS ####################
}
