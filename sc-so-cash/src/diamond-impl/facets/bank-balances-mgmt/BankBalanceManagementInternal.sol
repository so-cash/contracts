// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {
  ISoCashGlobalReferential, 
  BankIdentifier
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {
  ISoCashAccount,
  AccountNumber,
  AccountData,
  TransferId,
  OVERDRAFT_AMOUNT,
  CCY,
  BIC} from "../../../intf/so-cash-types.sol";
import {
  ISoCashBank,
  ISoCashBankBalanceManagementInternal,
  IERC20CompatibilityBaseInternal} from "../../../intf/so-cash-bank.sol";
import {IOwnable} from "../../../intf/whitelisted-senders.sol";
import {BankBalanceManagementStorage} from "./BankBalanceManagementStorage.sol";
import {LocalIBANCalculator} from "../iban/IBANService.sol";
import {SharedFunctions} from "../../libs/SharedFunctions.sol";

contract BankBalanceManagementInternal is IERC20CompatibilityBaseInternal, ISoCashBankBalanceManagementInternal {

  function _totalSupply() internal view returns (uint256) {
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    return l._totalSupply;
  }

  function _isActive(ISoCashAccount account) internal view returns (bool) {
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    return l._accounts[account].active;
  }

  modifier onlyRegisteredAccount() {
    require(_isRegistered(ISoCashAccount(msg.sender)), "SoC: Only a registered account can call this function");
    _;
  }

  function _isRegistered(ISoCashAccount account) internal view returns (bool) {
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    return l._accounts[account].registered;
  }

  function _registerAccount(ISoCashAccount account) internal returns (bool) {
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot register a null account");
    require(SharedFunctions._ioa(account).bank() == ISoCashBank(address(this)), "SoC: Cannot register an account not owned by this bank. Use transferOwnership first.");
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    AccountData storage ad = l._accounts[account];
    bool registered = ad.registered;
    if (registered) return true;

    if (!ad.active) { 
      // this is a new account let's initialize
      ad.registered = true;
      ad.active = true;
      ad.accountNumber = AccountNumber.wrap(uint32(l._accountNumberCounter++));
      ad.balance = 0;
      ad.lockedBalance = 0;
      ad.overdraftBalance = 0;
      l._accountNumbers[ad.accountNumber] = account;
      emit AccountActivation(account, true);
    } // called on an existing account
    emit AccountRegistration(account, true);

    // since the account's owner is this bank, we can allow the sender of this call to also be whitelisted
    SharedFunctions._iaw(account).whitelist(msg.sender);
    return true;
  }
  function _unregisterAccount(ISoCashAccount account) internal returns (bool) {
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot unregister a null account");
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    AccountData storage ad = l._accounts[account];
    bool registered = ad.registered;
    if (!registered) return true;

    // cannot unregister an account with a balance
    require(ad.balance + ad.overdraftBalance == 0, "SoC: Cannot unregister an account with a balance");

    // delete the record
    delete l._accounts[account];
    emit AccountRegistration(account, false);

    // return the ownership to the caller (ie the back office)
    IOwnable(address(account)).transferOwnership(msg.sender);
    return true;
  }

  function _toggleAccountActive(ISoCashAccount account) internal returns (bool) {
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot toggle a null account");
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    AccountData storage ad = l._accounts[account];
    require(ad.registered, "SoC: Cannot toggle an unregistered account");
    ad.active = !ad.active;
    emit AccountActivation(account, ad.active);
    return ad.active;
  }

  function _balanceOf(address account) internal view returns (uint256) {
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    AccountData storage ad = l._accounts[ISoCashAccount(account)];
    if (ad.overdraftBalance > ad.balance) return 0; // value is normally negative
    else {
      unchecked {
        return ad.balance - ad.overdraftBalance;
      }
    }
  }

  function _lockedBalanceOf(ISoCashAccount account) internal view returns (uint256) {
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    return l._accounts[account].lockedBalance;
  }

  function _unlockedBalanceOf(ISoCashAccount account) internal view returns (uint256) {
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    unchecked {
      if (l._accounts[account].balance >= l._accounts[account].lockedBalance) {
        return l._accounts[account].balance - l._accounts[account].lockedBalance;
      } else return 0;
    }
  }

  function _fullBalanceOf(ISoCashAccount account) internal view returns (int256) {
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    AccountData storage ad = l._accounts[account];
    unchecked {
      return int256(ad.balance - ad.overdraftBalance);
    }
  }

  function _accountNumberOf(ISoCashAccount account) internal view returns (AccountNumber) {
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    return l._accounts[account].accountNumber;
  }

  function _addressOf(AccountNumber accountNumber) internal view returns (ISoCashAccount) {
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    return l._accountNumbers[accountNumber];
  }

  function _decodeAccountString(string memory accountNumber11) internal pure returns (CCY, AccountNumber) {
    bytes memory ccy3 = new bytes(3);
    for (uint i = 0; i < 3; i++) {
      ccy3[i] = bytes(accountNumber11)[i];
    } 
    bytes memory account8 = new bytes(8);
    for (uint i = 3; i < 11; i++) {
      account8[i - 3] = bytes(accountNumber11)[i];
    }
    uint256 num = LocalIBANCalculator.frenchStringToNumber(string(abi.encodePacked(account8)));
    AccountNumber an = AccountNumber.wrap(uint32(num));
    return (CCY.wrap(bytes3(ccy3)), an);
  }
  function _addressOfFullAccount(string memory account) internal view returns (ISoCashAccount) {
    (, AccountNumber an) = _decodeAccountString(account);
    return _addressOf(an);
  }

  // From here the functions are used by other facets by inheritance of this internal contract

  function _editBalance(ISoCashAccount account, uint256 _credit, uint256 _debit, uint256 _addLock, uint256 _delLock) internal returns (uint256 newSupply) {
    // Will proceed to the balance adjustment taking into account overdraft and locked balance
    // No event is generated here, it is just consistency function for the 3 fields of the account data
    // The consistency between the 3 fields is
    // real balance: balance - overdraft
    // locked funds cannot be spent. Locking/unlocking cannot change the balance
    // cannot lock more than the positive cash: balance >= locked
    // No overdraft if unlocked balance is positive: balance - locked > 0 => overdraft = 0
    // No unlocked balance if overdraft is positive: overdraft > 0 => balance - locked = 0
    // locking an insufficient balance will create overdraft and put it in the balance
    // unlocking when there is overdraft will release overdraft using the positive balance

    // ERC20BaseStorage.Layout storage erc20 = ERC20BaseStorage.layout();
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    AccountData storage ad = l._accounts[account];

    if (_credit>0) {
      // add credit, reducing the overdraft first
      uint amt = _credit;
      if (ad.overdraftBalance >= amt) {
        unchecked {
          ad.overdraftBalance -= amt;
          amt = 0;
        }
      } if (ad.overdraftBalance>0) {
        unchecked {
          amt -= ad.overdraftBalance;
          ad.overdraftBalance = 0;
          ad.balance += amt;
          l._totalSupply += amt;
        }
      } else { // no overdraft
        ad.balance += amt;
        l._totalSupply += amt;
      }
    }

    if (_delLock > 0) {
      // decrease the locked balance
      require(ad.lockedBalance >= _delLock, "SoC: Insufficient locked funds");
      unchecked {
        ad.lockedBalance -= _delLock;
      }
      // try release overdraft with balance 
      if (ad.overdraftBalance > 0) {
        if (ad.lockedBalance < ad.balance) {
          uint256 net = ad.balance - ad.lockedBalance;
          if (ad.overdraftBalance > net) {
            unchecked {
              ad.overdraftBalance -= net;
              ad.balance -= net;
              l._totalSupply -= net;
            }
          } else {
            unchecked {
              ad.balance -= ad.overdraftBalance;
              l._totalSupply -= ad.overdraftBalance;
              ad.overdraftBalance = 0;
            }
          }
        }
      }
    }

    if (_addLock > 0) {
      // increase the lock and eventually take from the overdraft limit if needed
      if(ad.balance > ad.lockedBalance+_addLock) {
        // we have enough free balance, just lock it
        ad.lockedBalance += _addLock;
      } else {
        // we do not have enough so we need to get it from the overdraft
        unchecked {
          uint256 missing = ad.lockedBalance+_addLock - ad.balance;
          ad.overdraftBalance += missing;
          ad.balance += missing;
          l._totalSupply += missing;
          ad.lockedBalance += _addLock;
        }
      }
    } 

  
    if (_debit > 0 ) {
      // remove debit, take on overdraft only if needed and up to the limit
      unchecked {
        uint256 available = ad.balance - ad.lockedBalance;
        if (available >= _debit) {
          ad.balance -= _debit;
          l._totalSupply -= _debit;
          _debit = 0;
        } else if (available > 0) {
          ad.balance -= available;
          l._totalSupply -= available;
          _debit -= available;
          available = 0;
        }
        // _debit may have some balance left to use
        if (_debit>0) {
          // debit should be taken from overdraft
          ad.overdraftBalance += _debit;
        }
      }
    }

    // check the overdraft limit after the uopdates
    int limit = SharedFunctions._ioa(account).getAttributeNum(OVERDRAFT_AMOUNT);
    if (limit > 0) {
      require(ad.overdraftBalance <= uint256(limit), _addLock>0?"SoC: Overdraft limit would be reached, cannot lock the amount":"SoC: Overdraft limit would be reached, cannot debit account");
    } else {
      require(ad.overdraftBalance == 0, _addLock>0?"SoC: Insufficient unlocked funds":"SoC: Insufficient funds");
    }
    return l._totalSupply;
  }

  function _lock(ISoCashAccount account, uint256 amount) internal returns (bool){
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot lock funds of a null account");
    require(l._accounts[account].registered, "SoC: Cannot lock funds of an unregistered account");
    
    _editBalance(account, 0, 0, amount, 0);
    return true;
  }

  function _unlock(ISoCashAccount account, uint256 amount) internal returns (bool){
    BankBalanceManagementStorage.Layout storage l = BankBalanceManagementStorage.layout();
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot unlock funds of a null account");
    require(l._accounts[account].registered, "SoC: Cannot unlock funds of an unregistered account");
    
    _editBalance(account, 0, 0, 0, amount);
    return true;
  }

  function _transferMintBurnBalances(ISoCashAccount sender, ISoCashAccount recipient, uint256 amount, TransferId id) internal returns (bool){
    if (SharedFunctions.notNullAccount(sender)) _editBalance(sender, 0, amount, 0, 0);
    if (SharedFunctions.notNullAccount(recipient)) _editBalance(recipient, amount, 0, 0, 0);
    // ERC20 compatibility requirement
    emit Transfer(address(sender), address(recipient), amount);
    // events for SoCash with the id where to get more info
    emit TransferEx(sender, recipient, amount, id);
    return true;
  }

}