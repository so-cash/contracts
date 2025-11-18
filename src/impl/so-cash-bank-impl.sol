// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "../intf/so-cash-types.sol";
import "../intf/so-cash-bank.sol";
import "../intf/so-cash-account.sol";
import "../utilities/controls.sol";
import "../utilities/whitelisted-senders.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../utilities/IBAN.sol";

struct AccountData {
  bool registered;
  bool active;
  AccountNumber accountNumber;
  uint256 balance;
  uint256 lockedBalance;
  uint256 overdraftBalance;
  ISoCashBank loroOf; // can remain zero if not for a bank
}

contract SoCashBank is ISoCashBank, ISoCashBankBackOffice, ISoCashBankExternal, ISoCashInterBank, Controls, WhitelistedSenders {
  //#region STORAGE VARIABLES
  BIC private _bic;
  BankCode private _bankCode;
  BranchCode private _branchCode;
  CCY private _ccy;
  uint8 private _decimals;
  uint256 private _totalSupply;
  uint256 private _transferIdCounter = 1;
  uint256 private _accountNumberCounter = 1;
  IBANCalculator private _ibanCalc; // set by the method setIBANCalculator

  mapping(ISoCashAccount => AccountData) private _accounts;
  mapping(AccountNumber => ISoCashAccount) private _accountNumbers;
  mapping(ISoCashBank => CorrespondentBank) private _correspondents;
  mapping(BankCode => mapping(BranchCode => ISoCashBank)) private _codesToBanks;
  mapping(TransferId => TransferInfo) private _transferDetails;

  // event debug(string message, uint256 value, address add);
  // ********* The constructor *******
  constructor(BIC pBic, BankCode bankCode, BranchCode branchCode, CCY currency, uint8 nDecimals) {
    _bic = pBic;
    _bankCode = bankCode;
    _branchCode = branchCode;
    _ccy = currency;
    _decimals = nDecimals;
    // register our codes to ourselves
    _codesToBanks[_bankCode][_branchCode] = this;
    // Force the deployer to be whitelisted
    whitelist(msg.sender);
    emit BankCreation(this, string(abi.encodePacked(pBic)), string(abi.encodePacked(currency)));
  }

  function setIBANCalculator(IBANCalculator calc) public onlyWhitelisted() {
    _ibanCalc = calc;
  }

  // ********* The external functions *******
  //#region ACCOUNT's FUNCTIONS
  // function designed to be called by the accounts so the sender is the account

  modifier onlyRegisteredAccount() {
    require(isAccountRegistered(ISoCashAccount(msg.sender)), "SoC: Only a registered account can call this function");
    _;
  }

  function transferInfo(TransferId id) public view returns (TransferInfo memory) {
    return _transferDetails[id];
  }
  function transfer(RecipientInfo calldata to, uint256 amount, string calldata details) public onlyRegisteredAccount returns (bool) {
    TransferId id = _createTransferInfo(ISoCashAccount(msg.sender), to, amount, details);
    return _transferLogic(ISoCashAccount(msg.sender), to, amount, id);
  }

  function lockFunds(uint256 amount) external onlyRegisteredAccount returns (bool) {
    return _lock(ISoCashAccount(msg.sender), amount);
  }
  function unlockFunds(uint256 amount) external onlyRegisteredAccount returns (bool) {
    return _unlock(ISoCashAccount(msg.sender), amount);
  }
  function lockedBalanceOf(ISoCashAccount account) public view returns (uint256) {
    return _accounts[account].lockedBalance;
  }
  function unlockedBalanceOf(ISoCashAccount account) public view returns (uint256) {
    unchecked {
      if (_accounts[account].balance >= _accounts[account].lockedBalance) {
        return _accounts[account].balance - _accounts[account].lockedBalance;
      } else return 0;
    }
  }
  function balanceOf(address account) public view override returns (uint256) {
    AccountData storage ad = _accounts[ISoCashAccount(account)];
    if (ad.overdraftBalance > ad.balance) return 0; // value is normally negative
    else {
      unchecked {
        return ad.balance - ad.overdraftBalance;
      }
    }
  }

  function fullBalanceOf(ISoCashAccount account) public view returns (int256) {
    AccountData storage ad = _accounts[account];
    unchecked {
      return int256(ad.balance - ad.overdraftBalance);
    }
  }


  function totalSupply() public view override returns (uint256) {
    return _totalSupply;
  }

  function name() public view override returns (string memory) {
    // convert the _bic to string
    return string(abi.encodePacked(_bic));
  }

  function symbol() public view override returns (string memory) {
    return string(abi.encodePacked(_ccy));
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  function bic() public view returns (string memory) {
    return string(abi.encodePacked(_bic));
  }
  function codes() public view returns (BankCode, BranchCode) {
    return (_bankCode, _branchCode);
  }

  function ibanOf(ISoCashAccount account) public view returns (string memory) {
    AccountNumber an = _accounts[account].accountNumber;
    require(AccountNumber.unwrap(an) != 0, "SoC: Account not registered");
    require(address(_ibanCalc) != address(0), "SoC: IBAN calculator not set");

    string memory bankCode5 = string(abi.encodePacked(_bankCode));
    string memory branchCode5 = string(abi.encodePacked(_branchCode));
    string memory accountNumber11 = _ibanCalc.uintToString(AccountNumber.unwrap(an));
    bytes memory ccy = abi.encodePacked(_ccy);
    accountNumber11 = _ibanCalc.padWithZeros(accountNumber11, 8);
    accountNumber11 = string(abi.encodePacked(ccy[0], ccy[1], ccy[2], accountNumber11));
    string memory ibanStr = _ibanCalc.calculateFrenchIBAN(bankCode5, branchCode5, accountNumber11);
    return ibanStr;
    // IBAN iban = IBAN.wrap(bytes32(bytes(ibanStr)));
    // return string(abi.encodePacked(iban));
  }
  function accountNumberOf(ISoCashAccount account) public view returns (AccountNumber) {
    return _accounts[account].accountNumber;
  }
  function addressOf(AccountNumber accountNumber) public view returns (ISoCashAccount) {
    return _accountNumbers[accountNumber];
  }
  function decodeIBAN(string memory iban) public view returns (ISoCashBank bank, ISoCashAccount account) {
    (bool valid, string memory bankCode5, string memory branchCode5, string memory accountNumber11, ) = _ibanCalc.extractFrenchIBAN(iban);
    require(valid, "SoC: Invalid IBAN");
    // extract the number from the string, account starts with the 3 letters of the currency
    bytes memory ccy3 = new bytes(3);
    for (uint i = 0; i < 3; i++) {
      ccy3[i] = bytes(accountNumber11)[i];
    } 
    // Make sure the currency is the same as the one we are using in this module
    require(strcmp(string(ccy3), string(abi.encodePacked(_ccy))), "SoC: Currency mismatch");
    // (, bytes8 account8) = abi.decode(bytes(accountNumber11), (bytes3, bytes8));
    bytes memory account8 = new bytes(8);
    for (uint i = 3; i < 11; i++) {
      account8[i - 3] = bytes(accountNumber11)[i];
    }
    // require(false,string(abi.encodePacked("debug :", account8)));
    AccountNumber an = AccountNumber.wrap(uint32(_ibanCalc.frenchStringToNumber(string(abi.encodePacked(account8)))));
    // lookup the bank
    BankCode bCode = BankCode.wrap(bytes5(bytes32(bytes(bankCode5))));
    BranchCode brCode = BranchCode.wrap(bytes5(bytes32(bytes(branchCode5))));
    bank = _codesToBanks[bCode][brCode];
    if (notNullBank(bank)) {
      if (bank == this) {
        // the account is in this bank
        return (this, _accountNumbers[an]);
      } else {
        // the account is in another bank
        account = ISoCashBankExternal(address(bank)).addressOf(an);
        return (bank, account);
      }

    } else return (ZERO_BANK, ZERO_ACCOUNT);
  }

  //#region INTERBANK FUNCTIONS

  modifier onlyCorrespondentBank() {
    require(isCorrespondentRegistered(ISoCashBank(msg.sender)), "SoC: Only a correspondent bank can call this function");
    _;
  }

  function interbankTransfer(RecipientInfo calldata to, uint256 amount, TransferId id) public onlyCorrespondentBank returns (bool) {
    CorrespondentBank storage cb = _correspondents[ISoCashBank(msg.sender)];
    ISoCashBankExternal srcBank = ISoCashBankExternal(msg.sender);
    // create a transfer info from a copy of the recipient info
    TransferId localId = _copyTransferInfo(srcBank.transferInfo(id));

    // check that our nostro has been credited
    uint256 balance = _ioa(cb.nostro).balance();
    require(cb.lastNostroBalance + amount == balance, "SoC: Our nostro has not been credited");
    cb.lastNostroBalance = balance; // set the balance

    return _interbankTransferLogic(ISoCashBank(address(srcBank)), to, amount, localId);
  }
  function interbankNetting(uint256 amount, TransferId) public onlyCorrespondentBank returns (bool) {
    CorrespondentBank storage cb = _correspondents[ISoCashBank(msg.sender)];
    // ISoCashBankExternal srcBank = ISoCashBankExternal(msg.sender);
    // create a transfer info from a copy of the recipient info
    // This is a specific case where we need to invert the sender and recipient
    TransferId localId = _createTransferInfo(
      cb.loro, 
      RecipientInfo(cb.nostro, BIC.wrap(0), IBAN.wrap(0)), 
      amount, "Netting request");

    // check that our nostro has been debited
    uint256 balance = _ioa(cb.nostro).balance();
    // emit debug("balance of nostro", balance, address(cb.nostro));
    // emit debug("amount", amount, address(0));
    // emit debug("last nostro balance", cb.lastNostroBalance, address(0));
    require(cb.lastNostroBalance == balance + amount, "SoC: Our nostro has not been debited before this call");

    bool success = _burn(cb.loro, amount, localId);
    cb.lastNostroBalance = balance;
    return success;
  }
  function advice(uint256 amount, OperationDirection direction, TransferId id) public returns (bool) {
    CorrespondentBank storage cb = _correspondents[ISoCashBank(msg.sender)];
    // if (!cb.registered) return false;
    uint256 balance = _ioa(cb.nostro).balance();
    if (direction == OperationDirection.CREDIT) {
      require(cb.lastNostroBalance + amount == balance, "SoC: Our nostro has not been credited according to advice");
    } else {
      require(cb.lastNostroBalance == balance + amount, "SoC: Our nostro has not been debited according to advice");
    }
    cb.lastNostroBalance = balance;
    emit Adviced(this, cb.nostro, amount, direction, id);
    return true;
  }
  
  //#region BACKOFFICE FUNCTIONS
  // Correspondents management
  function registerCorrespondent(ISoCashBank bank, ISoCashAccount loro, ISoCashAccount nostro) public onlyWhitelisted returns (bool) {
    require(notNullBank(bank), "SoC: Cannot register a null bank");
    require(_sameDefinition(ISoCashBankExternal(address(bank))), "SoC: The bank does not have the same definition as this bank");
    CorrespondentBank storage cb = _correspondents[bank];
    bool exists = cb.registered;
    cb.loro = loro; // may be a null account
    cb.nostro = nostro; // may be a null account
    // get the codes of the bank
    (BankCode bCode, BranchCode brCode) = ISoCashBankExternal(address(bank)).codes();
    _codesToBanks[bCode][brCode] = bank;
    
    if (!exists) {
      cb.registered = true;
      emit BankRegistration(bank, true);
      if (isAccountRegistered(loro)) {
        _accounts[loro].loroOf = bank;
      }
    }
    return true;
  }
  function unregisterCorrespondent(ISoCashBank bank) public onlyWhitelisted returns (bool) {
    CorrespondentBank storage cb = _correspondents[bank];
    bool exists = cb.registered;
    if (exists) {
      cb.registered = false;
      emit BankRegistration(bank, false);
    }
    return true;
  }
  function isCorrespondentRegistered(ISoCashBank bank) public view returns (bool) {
    return _correspondents[bank].registered;
  }
  function correspondent(ISoCashBank bank) public view returns (CorrespondentBank memory) {
    return _correspondents[bank];
  }


  // Account management
  function registerAccount(ISoCashAccount account) public onlyWhitelisted returns (bool) {
    require(notNullAccount(account), "SoC: Cannot register a null account");
    require(_ioa(account).bank() == this, "SoC: Cannot register an account not owned by this bank. Use transferOwnership first.");
    AccountData storage ad = _accounts[account];
    bool registered = ad.registered;
    if (registered) return true;

    if (!ad.active) { 
      // this is a new account let's initialize
      ad.registered = true;
      ad.active = true;
      ad.accountNumber = AccountNumber.wrap(uint32(_accountNumberCounter++));
      ad.balance = 0;
      ad.lockedBalance = 0;
      ad.overdraftBalance = 0;
      _accountNumbers[ad.accountNumber] = account;
      emit AccountActivation(account, true);
    } // called on an existing account
    emit AccountRegistration(account, true);

    // since the account's owner is this bank, we can allow the sender of this call to also be whitelisted
    _iaw(account).whitelist(msg.sender);
    return true;
  }
  function unregisterAccount(ISoCashAccount account) public onlyWhitelisted returns (bool) {
    require(notNullAccount(account), "SoC: Cannot unregister a null account");
    AccountData storage ad = _accounts[account];
    bool registered = ad.registered;
    if (!registered) return true;

    // cannot unregister an account with a balance
    require(ad.balance + ad.overdraftBalance == 0, "SoC: Cannot unregister an account with a balance");

    // delete the record
    delete _accounts[account];
    emit AccountRegistration(account, false);
    return true;
  }
  function isAccountRegistered(ISoCashAccount account) public view returns (bool) {
    return _accounts[account].registered;
  }

  function toggleAccountActive(ISoCashAccount account) public returns (bool) {
    require(notNullAccount(account), "SoC: Cannot toggle a null account");
    AccountData storage ad = _accounts[account];
    require(ad.registered, "SoC: Cannot toggle an unregistered account");
    ad.active = !ad.active;
    emit AccountActivation(account, ad.active);
    return ad.active;
  }
  function isAccountActive(ISoCashAccount account) public view returns (bool) {
    return _accounts[account].active;
  }

  function credit(ISoCashAccount account, uint256 amount, string calldata details) public onlyWhitelisted returns (bool) {
    TransferId id = _createTransferInfo(
      ZERO_ACCOUNT, 
      RecipientInfo(account, BIC.wrap(0), IBAN.wrap(0)), 
      amount, details);
    bool success = _mint(account, amount, id);
    _adviceIfNeeded(account, amount, OperationDirection.CREDIT, id);
    return success;

  }

  function debit(ISoCashAccount account, uint256 amount, string calldata details) public onlyWhitelisted returns (bool) {
    TransferId id = _createTransferInfo(
      account, 
      RecipientInfo(ZERO_ACCOUNT, BIC.wrap(0), IBAN.wrap(0)), 
      amount, details);
    bool success = _burn(account, amount, id);
    _adviceIfNeeded(account, amount, OperationDirection.DEBIT, id);
    return success;
  }

  function lockFunds(ISoCashAccount account, uint256 amount) public onlyWhitelisted returns (bool) {
    return _lock(account, amount);
  }
  function unlockFunds(ISoCashAccount account, uint256 amount) public onlyWhitelisted returns (bool) {
    return _unlock(account, amount);
  }

  function transferFrom(ISoCashAccount from, RecipientInfo calldata to, uint256 amount, string calldata details) public onlyWhitelisted returns (bool) {
    TransferId id = _createTransferInfo(from, to, amount, details);
    return _transferLogic(from, to, amount, id);
  }


  function creditNostro(ISoCashAccount nostro, uint256 amount, string calldata details) public onlyWhitelisted() returns (bool) {
    require(notNullAccount(nostro), "SoC: Cannot credit a null nostro account");
    ISoCashBank cBank = ISoCashBank(getBankOf(address(nostro)));
    require(isCorrespondentRegistered(cBank), "SoC: The account is not a nostro of a registered correspondent bank");
    CorrespondentBank storage cb = _correspondents[cBank];
    require(cb.nostro == nostro, "SoC: The account is not your nostro at the correspondent bank");
    require(notNullAccount(cb.loro), "SoC: The correspondent bank has no loro account with you");
    RecipientInfo memory recipient = RecipientInfo(nostro, BIC.wrap(0), IBAN.wrap(0));
    TransferId id = _createTransferInfo(
      ZERO_ACCOUNT, 
      recipient, 
      amount, details);
    bool success = _mint(cb.loro, amount, id);
    // Call the correspondent bank to inform them of the credit via an interbank transfer
    success = success && _ibi(cBank).interbankTransfer(recipient, amount, id);
    cb.lastNostroBalance = _ioa(cb.nostro).balance();
    return success;
  }

  function requestNetting(ISoCashBank cBank, uint256 amount) public returns (bool) {
    require(notNullBank(cBank), "SoC: Cannot request netting with a null correspondent bank");
    CorrespondentBank storage cb = _correspondents[cBank];
    require(cb.registered, "SoC: The correspondent bank is not registered");
    require(notNullAccount(cb.loro), "SoC: The correspondent bank has no loro account with you");
    require(notNullAccount(cb.nostro), "SoC: The correspondent bank has no nostro account with you");
    require(_accounts[cb.loro].balance >= amount, "SoC: Insufficient funds for netting");
    TransferId id = _createTransferInfo(
      cb.loro, 
      RecipientInfo(cb.nostro, BIC.wrap(0), IBAN.wrap(0)), 
      amount, "Netting request");
    // debit their account on our end
    bool success = _burn(cb.loro, amount, id);
    // Call the correspondent bank to inform them of the netting via an interbank transfer
    success = success && _ibi(cBank).interbankNetting(amount, id);
    // require(success, "Interbank failed");
    // check we have been debited
    uint256 balance = _ioa(cb.nostro).balance();
    // require(cb.lastNostroBalance == balance + amount, "SoC: Our nostro has not been debited as requested");
    cb.lastNostroBalance = balance; // update the balance
    return success;
  }

  function synchroNostro(ISoCashAccount nostro) public onlyWhitelisted() returns (bool) {
    require(notNullAccount(nostro), "SoC: Cannot credit a null nostro account");
    ISoCashBank cBank = ISoCashBank(getBankOf(address(nostro)));
    require(isCorrespondentRegistered(cBank), "SoC: The account is not a nostro of a registered correspondent bank");
    CorrespondentBank storage cb = _correspondents[cBank];
    require(cb.nostro == nostro, "SoC: The account is not your nostro at the correspondent bank");
    cb.lastNostroBalance = _ioa(nostro).balance();
    return true;
  }

  function decidePendingTransfer(TransferId id, TransferStatus status, string memory reason) public onlyWhitelisted returns (bool) {
    TransferInfo storage ti = _transferDetails[id];
    require(ti.status == TransferStatus.PENDING, "SoC: The transfer is not pending");
    require(status == TransferStatus.CANCELLED || status == TransferStatus.PROCESSED, "SoC: Invalid status");
    
    ti.reason = _join(ti.reason, ", =>", reason);
    if (status == TransferStatus.CANCELLED) {
      // if the transfer is cancelled
      ti.status = TransferStatus.CANCELLED;
      emit TransfertStateChanged(id, TransferStatus.CANCELLED);
      return true;
    } 

    // Review the transaction to decide what operation to do
    if (notNullAccount(ti.sender)) {
      ISoCashBank srcBank = ISoCashBank(getBankOf(address(ti.sender)));
      if (srcBank == this) {
        if (notNullAccount(ti.recipient.account)) {
          // we have a transfer to another account
          return _transferLogic(ti.sender, ti.recipient, ti.amount, id);
        } else {
          if (IBAN.unwrap(ti.recipient.iban) == 0) {
            // we have a burn because there is no recipient defined
            return _burn(ti.sender, ti.amount, id);
          } else {
            // we have a transfer to a BIC/IBAN
            return _transferLogic(ti.sender, ti.recipient, ti.amount, id);
          }
        }
      } else { // the transfer is from another bank
        return _interbankTransferLogic(srcBank, ti.recipient, ti.amount, id);
      }
    } else { // we have a credit, only on a local account
      if (notNullAccount(ti.recipient.account)) {
        return _mint(ti.recipient.account, ti.amount, id);
      } else {
        require(false, "SoC: Situation not expected");
      }
    }

    require(false, "SoC: Should not be possible");
    return false;
  }

  //#region INTERNAL FUNCTIONS
  function _transferLogic(ISoCashAccount sender, RecipientInfo memory to, uint256 amount, TransferId id) internal returns (bool) {
    require(notNullAccount(sender), "SoC: Cannot transfer from a null account");
    // TODO
    // Identify the recipient as part of this bank or outside
    // Then decide if the operation should be put in pending or executed immediately
    // Then execute the action
    if (notNullAccount(to.account)) {
      // if sender and recipients are the same no operation to do
      if (sender == to.account) return true;
      require(sameCurrencyAndDecimals(_ioa(to.account), IERC20Metadata(address(this))), "SoC: Expect the recipient to have the same currency and decimals as the bank");
      // get the bank of the recipient
      ISoCashBank targetBank = ISoCashBank(getBankOf(address(to.account)));
      if (targetBank == this) {
        // the recipient is in the same bank, perform an account to account transfer
        bool success = _transfer(sender, to.account, amount, id);
        _adviceIfNeeded(sender, amount, OperationDirection.DEBIT, id);
        _adviceIfNeeded(to.account, amount, OperationDirection.CREDIT, id);
        return success;
      } else {
        // the recipient is in another bank
        CorrespondentBank storage cb = _correspondents[targetBank];
        if (cb.registered) {
          // the recipient is a correspondent bank
          // 2 options: Credit the loro of the bank or use our funds in our nostro with them to credit the beneficiary
          if (cb.lastNostroBalance >= amount) {
            // we have enough funds in nostro
            // we can debit the client and credit the beneficiary
            bool success = _burn(sender, amount, id);
            success = success &&
              _ioa(cb.nostro).transferEx(to, amount, _transferDetails[id].details);
            _adviceIfNeeded(sender, amount, OperationDirection.DEBIT, id);
            return success;
          } else {
            // we don't have enough funds in nostro
            // we need to credit the loro account of the correspondent bank
            bool success = _transfer(sender, cb.loro, amount, id);
            // and inform the correspondent bank of the request
            success = success &&
              _ibi(targetBank).interbankTransfer(to, amount, id);
            _adviceIfNeeded(sender, amount, OperationDirection.DEBIT, id);
            return success;
          }
        } else {
          // TODO
          // the recipient is not a correspondent bank
          // the operation try to find a routing bank or place the operation is pending
          require(false, "SoC: Non correspondent bank solution not implemented yet");
        }
      }

    } else {
      // If the recipient has no IBAN but a BIC and that the BIC is the same as the current bank then we burn as we are the recipient
      // if (BIC.unwrap(to.bic) == BIC.unwrap(_bic) && IBAN.unwrap(to.iban) == 0) {
      // Change: If only a BIC is pecified we expect a payment via central bank money, outside so|cash framework, so we burn the balance
      if (BIC.unwrap(to.bic) != 0 && IBAN.unwrap(to.iban) == 0) {
        bool success = _burn(sender, amount, id);
        _adviceIfNeeded(sender, amount, OperationDirection.DEBIT, id);
        return success;
      }
      // decode the IBAN to find the account and bank
      bytes memory ibanBytes = abi.encodePacked(to.iban);
      (/* ISoCashBank targetBank */, ISoCashAccount targetAccount) = decodeIBAN(string(abi.encodePacked(ibanBytes)));
      if (notNullAccount(targetAccount)) {
        to.account = targetAccount;
        return _transferLogic(sender, to, amount, id);
      } else
        require(false, "SoC: BIC/IBAN recipient not fully implemented yet");
    }
    return false; // just in case
  }

  function _interbankTransferLogic(ISoCashBank senderBank, RecipientInfo memory to, uint256 amount, TransferId id) internal returns (bool) {
    require(notNullBank(senderBank), "SoC: Cannot transfer from a null bank");
    // check what to do with the beneficiary
    if (notNullAccount(to.account)) {
      // get the bank of the recipient
      ISoCashBank targetBank = ISoCashBank(getBankOf(address(to.account)));
      if (targetBank == this) {
        // the recipient is in the same bank, perform an account to account transfer
        return _mint(to.account, amount, id);
      } else {
        // the recipient is in another bank (Not implemented)
        require(false, "SoC: Non correspondent bank solution not implemented yet");
      }
    } else {
      // TODO using BIC/IBAN addressing not implemented
      require(false, "SoC: BIC/IBAN recipient not implemented yet");
    }
    return false; // just in case
  }

  function _createTransferInfo(ISoCashAccount from, RecipientInfo memory to, uint256 amount, string memory details) internal returns (TransferId) {
    TransferId id = TransferId.wrap(_transferIdCounter++);
    _transferDetails[id] = TransferInfo(from, to, amount, TransferStatus.NEW, details, "");
    return id;
  }
  function _copyTransferInfo(TransferInfo memory ti) internal returns (TransferId) {
    // a copy of the transfer info is in NEW status on the receiving bank
    return _createTransferInfo(ti.sender, ti.recipient, ti.amount, ti.details);
  }
  function _setTransferStatus(TransferId id, TransferStatus status) internal {
    TransferInfo storage ti = _transferDetails[id];
    if (ti.status == TransferStatus.PENDING && status == TransferStatus.STP) {
      ti.status = TransferStatus.PROCESSED;
    } else {
      ti.status = status;
    }
    if (ti.status >= TransferStatus.PENDING) {
      emit TransfertStateChanged(id, ti.status);
    }
  }

  function _adviceIfNeeded(ISoCashAccount account, uint256 amount, OperationDirection direction, TransferId id) internal returns (bool){
    ISoCashInterBank cBank = ISoCashInterBank(address(_accounts[account].loroOf));
    if (isCorrespondentRegistered(ISoCashBank(address(cBank)))) {
      return cBank.advice(amount, direction, id);
    }
    return false;
  }

  enum ActionType { MINT, BURN, TRANSFER }

  // Note that this function can become an external library based code that can be changed on the fly by the back office
  function _shouldPlaceInPending(ISoCashAccount from, ISoCashAccount to, TransferInfo storage t, ActionType /*action*/) internal returns (bool) {
    // using the status to determine if it is a new transaction or a pending that is retested
    if (t.status != TransferStatus.NEW) return false;
    bool result = false;
    if (notNullAccount(from)) {
      AccountData storage ad = _accounts[from];

      // disable funds movement on inactive accounts
      if (!ad.active) {
        t.reason = string(abi.encodePacked(t.reason, result?", ":"", "Inactive sender account"));
        result = true;
      }
      
      // other conditions on sender here
    }
    if (notNullAccount(to)) {
      AccountData storage ad = _accounts[to];
      // disable funds movement on inactive accounts
      if (!ad.active) {
        t.reason = string(abi.encodePacked(result?", ":"", "Inactive recipient account"));
        result = true;
      }      
      // other conditions on recipient here
    }
    return result;
  }

  function _editBalance(ISoCashAccount account, uint256 _credit, uint256 _debit, uint256 _addLock, uint256 _delLock) internal {
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


    AccountData storage ad = _accounts[account];

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
          _totalSupply += amt;
        }
      } else { // no overdraft
        ad.balance += amt;
        _totalSupply += amt;
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
              _totalSupply -= net;
            }
          } else {
            unchecked {
              ad.balance -= ad.overdraftBalance;
              _totalSupply -= ad.overdraftBalance;
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
          _totalSupply += missing;
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
          _totalSupply -= _debit;
          _debit = 0;
        } else if (available > 0) {
          ad.balance -= available;
          _totalSupply -= available;
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
    int limit = _ioa(account).getAttributeNum(OVERDRAFT_AMOUNT);
    if (limit > 0) {
      require(ad.overdraftBalance <= uint256(limit), _addLock>0?"SoC: Overdraft limit would be reached, cannot lock the amount":"SoC: Overdraft limit would be reached, cannot debit account");
    } else {
      require(ad.overdraftBalance == 0, _addLock>0?"SoC: Insufficient unlocked funds":"SoC: Insufficient funds");
    }
  }

  function _mint(ISoCashAccount account, uint256 amount, TransferId id) internal returns (bool){
    require(notNullAccount(account), "SoC: Cannot credit a null account");
    // require(_accounts[account].active, "SoC: Cannot credit an inactive or unregistered account");

    if (_shouldPlaceInPending(ZERO_ACCOUNT, account, _transferDetails[id], ActionType.MINT)) {
      _setTransferStatus(id, TransferStatus.PENDING);
      return false;
    }
    _editBalance(account, amount, 0, 0, 0);
    // _totalSupply += amount;
    emit Transfer(address(0), address(account), amount);
    emit TransferEx(ZERO_ACCOUNT, account, amount, id);
    _setTransferStatus(id, TransferStatus.STP);
    return true;
  }

  function _burn(ISoCashAccount account, uint256 amount, TransferId id) internal returns (bool){
    require(notNullAccount(account), "SoC: Cannot debit a null account");
    // require(_accounts[account].active, "SoC: Cannot debit an inactive or unregistered account");

    if (_shouldPlaceInPending(account, ZERO_ACCOUNT, _transferDetails[id], ActionType.BURN)) {
      _setTransferStatus(id, TransferStatus.PENDING);
      return false;
    }
    _editBalance(account, 0, amount, 0, 0);
    emit Transfer(address(account), address(0), amount);
    emit TransferEx(account, ZERO_ACCOUNT, amount, id);
    _setTransferStatus(id, TransferStatus.STP);
    return true;
  }

  function _transfer(ISoCashAccount sender, ISoCashAccount recipient, uint256 amount, TransferId id) internal returns (bool){
    require(notNullAccount(sender), "SoC: Cannot transfer from a null account");
    require(notNullAccount(recipient), "SoC: Cannot transfer to a null account");
    // require(_accounts[sender].active, "SoC: Cannot transfer from an inactive or unregistered account");
    // require(_accounts[recipient].active, "SoC: Cannot transfer to an inactive or unregistered account");
    
    if (_shouldPlaceInPending(sender, recipient, _transferDetails[id], ActionType.TRANSFER)) {
      _setTransferStatus(id, TransferStatus.PENDING);
      return false;
    }

    _editBalance(sender, 0, amount, 0, 0);
    _editBalance(recipient, amount, 0, 0, 0);
    emit Transfer(address(sender), address(recipient), amount);
    emit TransferEx(sender, recipient, amount, id);
    _setTransferStatus(id, TransferStatus.STP);
    return true;
  }


  function _lock(ISoCashAccount account, uint256 amount) internal returns (bool){
    require(notNullAccount(account), "SoC: Cannot lock funds of a null account");
    require(_accounts[account].registered, "SoC: Cannot lock funds of an unregistered account");
    
    _editBalance(account, 0, 0, amount, 0);
    return true;
  }

  function _unlock(ISoCashAccount account, uint256 amount) internal returns (bool){
    require(notNullAccount(account), "SoC: Cannot unlock funds of a null account");
    require(_accounts[account].registered, "SoC: Cannot unlock funds of an unregistered account");
    
    _editBalance(account, 0, 0, 0, amount);
    return true;
  }



  //#region INTERNAL UTILITY FUNCTIONS

  function _sameDefinition(ISoCashBankExternal bank) internal view returns (bool) {
      if (!isContract(address(bank))) return false;
      return strcmp(bank.symbol(), string(abi.encodePacked(_ccy))) && bank.decimals() == _decimals;
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
  function _join(string memory a, string memory link, string memory b) internal pure returns(string memory) {
    if (bytes(a).length == 0) return b;
    else return string(abi.encodePacked(a, link, b));
  }
}
