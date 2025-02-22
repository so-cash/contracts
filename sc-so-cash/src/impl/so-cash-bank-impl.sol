// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "../intf/so-cash-types.sol";
import "../intf/so-cash-bank.sol";
import "../intf/so-cash-account.sol";
import "../utilities/whitelisted-senders.sol";
import "./payment-engine.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISoCashGlobalReferential, ISoCashCountryReferential, BankIdentifier, CodeType} from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";

import "../utilities/IBAN.sol";
import "../utilities/shared-lib.sol";



contract SoCashBank is ISoCashBank, ISoCashBankBackOffice, ISoCashBankExternal, ISoCashInterBank, WhitelistedSenders {
  string public constant version = "2.0.0";
  //#region STORAGE VARIABLES
  BIC private _bic;
  BankIdentifier private _bankId;
  CCY private _ccy;
  uint8 private _decimals;
  uint256 private _totalSupply;
  uint256 private _transferIdCounter = 1;
  uint256 private _accountNumberCounter = 1;
  ISoCashGlobalReferential private _routingRef; // set by the methof setRouterReferential

  mapping(ISoCashAccount => AccountData) private _accounts;
  mapping(AccountNumber => ISoCashAccount) private _accountNumbers;
  // mapping(ISoCashBank => CorrespondentBank) private _correspondents;
  // address of bank or erc20 => nostro structure. One single nostro by bank for the moment
  mapping(address => NostroAccount) private _nostros;
  // mapping(BankCode => mapping(BranchCode => ISoCashBank)) private _codesToBanks;
  mapping(TransferId => TransferInfo) private _transferDetails;

  using PaymentEngine for SoCashBank;
  using IBANCalculator for SoCashBank;
  using SharedFunctions for *;

  // event debug(string message, uint256 value, address add);
  event ExplainPlan(ExecutionPlan plan);
  // ********* The constructor *******
  constructor(ISoCashGlobalReferential routingRef, BIC pBic, BankIdentifier memory pId, CCY currency, uint8 nDecimals) {
    _routingRef = routingRef;
    _bic = pBic;
    _bankId = pId;
    _ccy = currency;
    _decimals = nDecimals;
    // register our codes to ourselves - to be removed
    // _codesToBanks[_bankCode][_branchCode] = this;
    // Force the deployer to be whitelisted
    whitelist(msg.sender);
    emit BankCreation(this, string(abi.encodePacked(pBic)), string(abi.encodePacked(currency)));
  }

  // function setIBANCalculator(IBANCalculator calc) public onlyWhitelisted() {
  //   _ibanCalc = calc;
  // }

  function getCountryReferential() public view returns (ISoCashCountryReferential) {
    ISoCashCountryReferential country = _routingRef.getCountry(_bankId.country);
    require(address(country)!=address(0), string(abi.encodePacked("SoC: Country ref ", _bankId.country, " not found")));
    return country;
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
  function transfer(RecipentInfo calldata to, uint256 amount, string calldata details) public onlyRegisteredAccount returns (bool) {
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
  function codes() public view returns (CodeType, CodeType) {
    return (_bankId.codes[0], _bankId.codes[1]);
  }

  // function toCodeType(bytes5 v) internal pure returns (CodeType result) {
  //   assembly {
  //     result:=v
  //   }
  // }
  function bankIdentifier() public view returns (BankIdentifier memory id) {
    return _bankId;
  }

  function ibanOf(ISoCashAccount account) public view returns (string memory) {
    AccountNumber an = _accounts[account].accountNumber;
    return this.ibanOfAccount(_bankId, _ccy, an);
  }
  function accountNumberOf(ISoCashAccount account) public view returns (AccountNumber) {
    return _accounts[account].accountNumber;
  }
  function addressOf(AccountNumber accountNumber) public view returns (ISoCashAccount) {
    return _accountNumbers[accountNumber];
  }

  function addressOfFullAccount(string memory account) public view returns (ISoCashAccount) {
    return resolveLocalAccount(account);
  }

  function decodeIBAN(string memory iban) public view returns (ISoCashBank bank, ISoCashAccount account) {
    BankAccount memory ba = this.decodeIBANIntoBankAccount(_routingRef, iban);
    return (ISoCashBank(ba.bank), ISoCashAccount(ba.account));
  }

  //#region INTERBANK FUNCTIONS

  modifier onlyCorrespondentBank() {
    require(isCorrespondentRegistered(ISoCashBank(msg.sender)), "SoC: Only a correspondent bank can call this function");
    _;
  }

  function interbankTransfer(BankAccount calldata ssi, RecipentInfo calldata to, uint256 amount, TransferId id) public onlyCorrespondentBank returns (bool) {
    ISoCashBankExternal srcBank = ISoCashBankExternal(msg.sender);
    // create a transfer info from a copy of the recipient info
    TransferId localId = _copyTransferInfo(srcBank.transferInfo(id));

    // check that the ssi that was used by the calling bank is actually a nostro at our level
    this.checkNostroBalanceAdjusted(_nostros, ssi, int256(amount));

    return _interbankTransferLogic(ISoCashBank(address(srcBank)), to, amount, localId);
  }
  function interbankNetting(uint256 amount, TransferId id) public onlyCorrespondentBank returns (bool) {
    NostroAccount storage nostro = _nostros[msg.sender];
    require(nostro.model == BankModel.SO_CASH, "SoC: Netting only supported for so-cash accounts");
    TransferInfo memory info = ISoCashBankExternal(msg.sender).transferInfo(id);
    ISoCashAccount loro = info.recipient.account;
    require(isAccountRegistered(loro), "SoC: Netting account not registered");
    // create a transfer info from a copy of the recipient info
    // This is a specific case where we need to invert the sender and recipient
    TransferId localId = _createTransferInfo(
      loro, 
      RecipentInfo(ISoCashAccount(nostro.account), BIC.wrap(0), IBAN.wrap(0)), 
      amount, "Netting request");

    // check that our nostro has been debited
    this.checkNostroBalanceAdjusted(_nostros, BankAccount(BankModel.SO_CASH, nostro.bank, nostro.account), - int256(amount));

    // int256 balance = ISoCashOwnedAccount(nostro.account).fullBalance();
    // // emit debug("balance of nostro", balance, address(cb.nostro));
    // // emit debug("amount", amount, address(0));
    // // emit debug("last nostro balance", cb.lastNostroBalance, address(0));
    // require(nostro.lastBalance == balance + int256(amount), "SoC: Our nostro has not been debited before this call");

    bool success = _transferMintBurn(ActionType.BURN, loro, ZERO_ACCOUNT, amount, localId);
    // nostro.lastBalance = balance;
    return success;
  }


  // function checkNostroBalanceAdjusted(BankAccount memory ssi, int256 amount) internal returns (bool) {
  //   // check that the nostro at bank that was used by the calling bank is actually a nostro at our level
  //   NostroAccount storage nostro = _nostros[ssi.bank];
  //   require(nostro.account == ssi.account && nostro.model == ssi.model, "SoC: The account provided is not a nostro account");
    
  //   // We have 2 scenario to cover. One where the nostro has been updated via an Advise call, and one where it was not
  //   if (nostro.lastBlock == block.number) { // Advice was called, the balance is already updated
  //     require(nostro.lastAdviceAmount == amount, "SoC: Our nostro has not been credited of the right amount");
  //   } else {
  //     // check that our nostro has been updated and update it locally
  //     int256 balance = PaymentEngine.getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);
  //     require(nostro.lastBalance + amount == balance, "SoC: Our nostro not been updated according to the amount");
  //     nostro.lastBalance = balance;
  //     nostro.lastBlock = block.number;
  //     nostro.lastAdviceAmount = amount;
  //   }
    
  //   return true;
  // }


  function advice(uint256 amount, OperationDirection direction, TransferId id) public returns (bool) {
    NostroAccount storage nostro = _nostros[msg.sender];
    if (this.adviceNostro(nostro, amount, direction, id)) {
      emit Adviced(this, ISoCashAccount(nostro.account), amount, direction, id);
    }
    return true;
  }
  
  //#region BACKOFFICE FUNCTIONS
  
  function isCorrespondentRegistered(ISoCashBank bank) public view returns (bool) {
    if (!SharedFunctions.notNullBank(bank)) return false;
    ISoCashCountryReferential country = getCountryReferential();
    // get the identifier of the calling bank
    BankIdentifier memory caller = SharedFunctions._ibe(bank).bankIdentifier();
    bool isCB = country.isCorrespondent(_bankId.codes, CCY.unwrap(_ccy), caller);
    return isCB;
  }

  // Not used. TODO: remove
  function correspondent(ISoCashBank bank) public view returns (BankIdentifier memory) {
    if (isCorrespondentRegistered(bank)) {
      return SharedFunctions._ibe(bank).bankIdentifier();
    } else {
      return BankIdentifier(0x0000, new CodeType[](0));
    }
  }


  // Account management
  function registerAccount(ISoCashAccount account) public onlyWhitelisted returns (bool) {
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot register a null account");
    require(SharedFunctions._ioa(account).bank() == this, "SoC: Cannot register an account not owned by this bank. Use transferOwnership first.");
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
    SharedFunctions._iaw(account).whitelist(msg.sender);
    return true;
  }
  function unregisterAccount(ISoCashAccount account) public onlyWhitelisted returns (bool) {
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot unregister a null account");
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
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot toggle a null account");
    AccountData storage ad = _accounts[account];
    require(ad.registered, "SoC: Cannot toggle an unregistered account");
    ad.active = !ad.active;
    emit AccountActivation(account, ad.active);
    return ad.active;
  }
  function isAccountActive(ISoCashAccount account) public view returns (bool) {
    return _accounts[account].active;
  }

  function getNostroBalance(address bank, address) public view returns (int256 actual, int256 last) {
    NostroAccount storage nostro = _nostros[bank];
    last = nostro.lastBalance;
    actual = PaymentEngine.getNostroBalanceByModel(nostro.model, bank, nostro.account);
  }


  function registerNostroAccount(BankAccount calldata nostro) public onlyWhitelisted returns (bool) {
    require(nostro.model != BankModel.UNDEFINED, "SoC: Cannot register an undefined nostro model");
    require(address(nostro.bank) != address(0), "SoC: Cannot register a null bank nostro");
    require(address(nostro.account) != address(0), "SoC: Cannot register a null account nostro");
    if (nostro.model == BankModel.SO_CASH) {
      require(ISoCashOwnedAccount(nostro.account).bank() == ISoCashBank(nostro.bank), "SoC: Inconsistent bank and account");
    }
    int256 balance = PaymentEngine.getNostroBalanceByModel(nostro.model, address(nostro.bank), address(nostro.account));

    _nostros[nostro.bank] = NostroAccount(nostro.model, address(nostro.bank), address(nostro.account), balance, 0, 0);
    emit NostroAccountRegistration(nostro.model, nostro.bank, nostro.account, true);
    return true;
  }

  function unregisterNostroAccount(address bank, address ) public onlyWhitelisted returns (bool) {
    NostroAccount storage nostro = _nostros[bank];
    if (nostro.model == BankModel.UNDEFINED) return false;
    // Need to emit before because else the nostro.bank, nostro.account are zeroed after the delete
    emit NostroAccountRegistration(nostro.model, nostro.bank, nostro.account, false);
    delete _nostros[bank];
    return true;
  }

  function nostroAccountModel(address bank, address) public view returns (BankModel) {
    return _nostros[bank].model;
  }


  function credit(ISoCashAccount account, uint256 amount, string calldata details) public onlyWhitelisted returns (bool) {
    TransferId id = _createTransferInfo(
      ZERO_ACCOUNT, 
      RecipentInfo(account, BIC.wrap(0), IBAN.wrap(0)), 
      amount, details);
    bool success = _transferMintBurn(ActionType.MINT, ZERO_ACCOUNT, account, amount, id);
    _adviceIfNeeded(account, amount, OperationDirection.CREDIT, id);
    return success;

  }

  function debit(ISoCashAccount account, uint256 amount, string calldata details) public onlyWhitelisted returns (bool) {
    TransferId id = _createTransferInfo(
      account, 
      RecipentInfo(ZERO_ACCOUNT, BIC.wrap(0), IBAN.wrap(0)), 
      amount, details);
    bool success = _transferMintBurn(ActionType.BURN, account, ZERO_ACCOUNT, amount, id);
    _adviceIfNeeded(account, amount, OperationDirection.DEBIT, id);
    return success;
  }

  function lockFunds(ISoCashAccount account, uint256 amount) public onlyWhitelisted returns (bool) {
    return _lock(account, amount);
  }
  function unlockFunds(ISoCashAccount account, uint256 amount) public onlyWhitelisted returns (bool) {
    return _unlock(account, amount);
  }

  function transferFrom(ISoCashAccount from, RecipentInfo calldata to, uint256 amount, string calldata details) public onlyWhitelisted returns (bool) {
    TransferId id = _createTransferInfo(from, to, amount, details);
    return _transferLogic(from, to, amount, id);
  }

  // function simulateTransfer(ISoCashAccount from, RecipentInfo calldata to, uint256 amount, string calldata details) public onlyWhitelisted returns (ExecutionPlan memory) {
  //   TransferId id = _createTransferInfo(from, to, amount, details);
  //   return this.transferExecutionPlan(_nostros, _routingRef, from, to, amount, id);
  // }


  function requestNetting(ISoCashBank cBank, ISoCashAccount loro, uint256 amount) public returns (bool) {
    require(SharedFunctions.notNullBank(cBank), "SoC: Cannot request netting with a null correspondent bank");
    NostroAccount storage nostro = _nostros[address(cBank)];
    require(nostro.model == BankModel.SO_CASH, "SoC: The bank does not have a so-cash nostro account for you");
    require(isAccountRegistered(loro), "SoC: Cannot request netting with an invalid loro account");

    require(_accounts[loro].balance >= amount, "SoC: Insufficient funds for netting");
    TransferId id = _createTransferInfo(
      loro, 
      RecipentInfo(ISoCashAccount(nostro.account), BIC.wrap(0), IBAN.wrap(0)), 
      amount, "Netting request");
    // debit their account on our end
    bool success = _transferMintBurn(ActionType.BURN, loro, ZERO_ACCOUNT, amount, id);
    // Call the correspondent bank to inform them of the netting via an interbank transfer
    success = success && SharedFunctions._ibi(cBank).interbankNetting(amount, id);
    // require(success, "Interbank failed");
    // check we have been debited
    success = success && this.checkNostroBalanceAdjusted(_nostros, BankAccount(BankModel.SO_CASH, nostro.bank, nostro.account), - int256(amount));
    return success;
  }

  function synchroNostro(address bank, address) public onlyWhitelisted() returns (bool) {
    NostroAccount storage nostro = _nostros[bank];
    require(nostro.model != BankModel.UNDEFINED, "SoC: The bank does not have a nostro account for you");

    nostro.lastBalance = PaymentEngine.getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);
    nostro.lastBlock = 0;
    nostro.lastAdviceAmount = 0;
    return true;
  }

  function decidePendingTransfer(TransferId id, TransferStatus status, string memory reason) public onlyWhitelisted returns (bool) {
    TransferInfo storage ti = _transferDetails[id];
    require(ti.status == TransferStatus.PENDING, "SoC: The transfer is not pending");
    require(status == TransferStatus.CANCELLED || status == TransferStatus.PROCESSED, "SoC: Invalid status");
    
    ti.reason = SharedFunctions._join(ti.reason, ", =>", reason);
    if (status == TransferStatus.CANCELLED) {
      // if the transfer is cancelled
      ti.status = TransferStatus.CANCELLED;
      emit TransfertStateChanged(id, TransferStatus.CANCELLED);
      return true;
    } 

    // Review the transaction to decide what operation to do
    if (SharedFunctions.notNullAccount(ti.sender)) {
      ISoCashBank srcBank = ISoCashBank(SharedFunctions.getBankOf(address(ti.sender)));
      if (srcBank == this) {
        if (SharedFunctions.notNullAccount(ti.recipient.account)) {
          // we have a transfer to another account
          return _transferLogic(ti.sender, ti.recipient, ti.amount, id);
        } else {
          if (IBAN.unwrap(ti.recipient.iban) == 0) {
            // we have a burn because there is no recipient defined
            return _transferMintBurn(ActionType.BURN, ti.sender, ZERO_ACCOUNT, ti.amount, id);
          } else {
            // we have a transfer to a BIC/IBAN
            return _transferLogic(ti.sender, ti.recipient, ti.amount, id);
          }
        }
      } else { // the transfer is from another bank
        return _interbankTransferLogic(srcBank, ti.recipient, ti.amount, id);
      }
    } else { // we have a credit, only on a local account
      if (SharedFunctions.notNullAccount(ti.recipient.account)) {
        return _transferMintBurn(ActionType.MINT, ZERO_ACCOUNT, ti.recipient.account, ti.amount, id);
      } else {
        require(false, "SoC: Situation not expected");
      }
    }

    require(false, "SoC: Should not be possible");
    return false;
  }

  function simulateTransfer(ISoCashAccount fromAccount, RecipentInfo memory to, uint256 amount) public view returns (ExecutionPlan memory) {
    TransferId id = TransferId.wrap(0);
    return this.transferExecutionPlan(_nostros, _routingRef, fromAccount, to, amount, id);
  }
  function simulateInterbankTransfer(ISoCashBank fromBank, RecipentInfo memory to, uint256 amount) public view returns (ExecutionPlan memory plan) {
    TransferId id = TransferId.wrap(0);
    plan = this.interbankExecutionPlan(_nostros, _routingRef, fromBank, to, amount, id);
    plan.debitLocalAccount = ZERO_ACCOUNT;
    return plan;
  }

  //#region INTERNAL FUNCTIONS

  function _transferLogic(ISoCashAccount sender, RecipentInfo memory to, uint256 amount, TransferId id) internal returns (bool) {

    ExecutionPlan memory plan = this.transferExecutionPlan(_nostros, _routingRef, sender, to, amount, id);
    emit ExplainPlan(plan);
    return _executePlan(id, plan);
  }

  function _interbankTransferLogic(ISoCashBank senderBank, RecipentInfo memory to, uint256 amount, TransferId id) internal returns (bool) {

    ExecutionPlan memory plan = this.interbankExecutionPlan(_nostros, _routingRef, senderBank, to, amount, id);
    emit ExplainPlan(plan);
    return _executePlan(id, plan);
  }


  function resolveLocalAccount(string memory accountNumber11) public view returns (ISoCashAccount) {
    AccountNumber an = this.decodeAccountNumber(accountNumber11);
    return _accountNumbers[an];
  }

  function _executePlan(TransferId id, ExecutionPlan memory plan) internal returns (bool) {
    TransferInfo storage ti = _transferDetails[id];
    bool success = true;
    int8 controlConsistency = 0; // A liability increase does +1, a liability decrease does -1, we should have zero at the end

    // ATTENTION, the plan.debitLocalAccount/creditLocalAccont can be this address when interbank (to solve a stack depth issue)
    // Fix this and set the controlConsistency accordingly
    if (address(plan.debitLocalAccount) == address(this)) {
      plan.debitLocalAccount = ZERO_ACCOUNT;
      controlConsistency--; // because it means that we have been credited in a nostro outside
    }
    if (address(plan.creditLocalAccount) == address(this)) {
      plan.creditLocalAccount = ZERO_ACCOUNT;
      controlConsistency++; // because it means that we have been debited in a nostro outside
    }

    // first process the local accounts (we do not check that the account are locals again)
    bool hasLocalDebit = SharedFunctions.notNullAccount(plan.debitLocalAccount);
    bool hasLocalCredit = SharedFunctions.notNullAccount(plan.creditLocalAccount);
    bool mustPayFromNostro = SharedFunctions.notNullAccount(plan.payFromNostro);
    bool mustPayViaCorrespondent = SharedFunctions.notNullBank(plan.payViaBank);

    if (hasLocalDebit && hasLocalCredit) {
      // no change in the consistency control
      if (plan.debitLocalAccount == plan.creditLocalAccount) {
        // we have the same account to debit and credit, 
        // we MUST, do a BURN and advice, then MINT and advice, so that the interbank call if any will need to see that it has been credited
        success = success && _transferMintBurn(ActionType.BURN, plan.debitLocalAccount, ZERO_ACCOUNT, ti.amount, id);
        _adviceIfNeeded(plan.debitLocalAccount, ti.amount, OperationDirection.DEBIT, id);
        success = success && _transferMintBurn(ActionType.MINT, ZERO_ACCOUNT, plan.creditLocalAccount, ti.amount, id);
        _adviceIfNeeded(plan.creditLocalAccount, ti.amount, OperationDirection.CREDIT, id);
      } else {
        // we have a local transfer - no change in the control
        success = success && _transferMintBurn(ActionType.TRANSFER, plan.debitLocalAccount, plan.creditLocalAccount, ti.amount, id);
        _adviceIfNeeded(plan.creditLocalAccount, ti.amount, OperationDirection.CREDIT, id);
        _adviceIfNeeded(plan.debitLocalAccount, ti.amount, OperationDirection.DEBIT, id);
      }
      // we can still have an interbank here
    } else if (hasLocalDebit) {
      success = success && _transferMintBurn(ActionType.BURN, plan.debitLocalAccount, ZERO_ACCOUNT, ti.amount, id);
      _adviceIfNeeded(plan.debitLocalAccount, ti.amount, OperationDirection.DEBIT, id);
      controlConsistency--;
    } else if (hasLocalCredit) {
      success = success && _transferMintBurn(ActionType.MINT, ZERO_ACCOUNT, plan.creditLocalAccount, ti.amount, id);
      _adviceIfNeeded(plan.creditLocalAccount, ti.amount, OperationDirection.CREDIT, id);
      controlConsistency++;
    }

    if (mustPayFromNostro) {
      // TODO: the recipient could be the nostro account of the correspondent bank in the evolution
      success = success && SharedFunctions._ioa(plan.payFromNostro).transferEx(ti.recipient, ti.amount, ti.details);
      controlConsistency++; // we have debited our nostro, so reduced our asset, so like increase our liability
    } else /* we cannot have both at the same time */ 
    if (mustPayViaCorrespondent) {
      // if we have a local credit then this is the account credited for the correspondent
      if (hasLocalCredit) {
        // we have a local credit, we must inform the correspondent bank
        success = success && SharedFunctions._ibi(plan.payViaBank).interbankTransfer(
          BankAccount(BankModel.SO_CASH, address(this), address(plan.creditLocalAccount)), 
          ti.recipient, ti.amount, id);
        // there is no change in the consistency control, the correspondent bank has been paid already on its account with us
      } else // we must have a payViaAccount and payToAccount
      if (plan.payViaAccount.model != BankModel.UNDEFINED && plan.payToAccount.model != BankModel.UNDEFINED) {
        // execute the payment depending on the model
        NostroAccount storage nostro = _nostros[plan.payViaAccount.bank];
        if (plan.payViaAccount.model == BankModel.SO_CASH) {
          success = success && ISoCashOwnedAccount(plan.payViaAccount.account).transferEx(
            RecipentInfo(ISoCashAccount(plan.payToAccount.account), BIC.wrap(0), IBAN.wrap(0)), ti.amount, ti.details);
          controlConsistency++; // we have debited our nostro, so reduced our asset, so like increase our liability
        } else if (plan.payViaAccount.model == BankModel.ERC20) {
          if (plan.payViaAccount.account == address(this)) {
            // require(false, "debug: payviaaccount is this bank");
            // Here the source account is this smart contract so we can call transfer directly
            success = success && IERC20Metadata(plan.payViaAccount.bank).transfer(plan.payToAccount.account, ti.amount);
            controlConsistency++; // we have debited our ERC20 nostro, so reduced our asset, so like increase our liability
          } else {
            // require(false, "debug: payviaaccount is not this bank");
            // Here the source account is another address that should have approved this contract to transfer on its behalf
            success = success && IERC20Metadata(plan.payViaAccount.bank).transferFrom(plan.payViaAccount.account, plan.payToAccount.account, ti.amount);
            controlConsistency++; // we have debited our nostro, so reduced our asset, so like increase our liability
          }
        }
        // need to update the local balance of the nostro account
        // nostro.lastBalance = nostro.lastBalance - int256(ti.amount);
        nostro.lastBalance = PaymentEngine.getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);
        success = success && SharedFunctions._ibi(plan.payViaBank).interbankTransfer(
          plan.payToAccount, ti.recipient, ti.amount, id);
      }
    }

    require(controlConsistency == 0, "SoC: Inconsistent execution plan");
    return success;
  }

  function _createTransferInfo(ISoCashAccount from, RecipentInfo memory to, uint256 amount, string memory details) internal returns (TransferId) {
    TransferId id = TransferId.wrap(_transferIdCounter++);
    _transferDetails[id] = TransferInfo(from, to, block.timestamp, amount, TransferStatus.NEW, details, "");
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
    if (SharedFunctions.notNullAccount(account)) {

      ISoCashInterBank cBank = ISoCashInterBank(SharedFunctions._ioa(account).getAttributeAddr(SO_CASH_BANK));
      // if (isCorrespondentRegistered(ISoCashBank(address(cBank)))) {
      if (SharedFunctions.notNullBank(ISoCashBank(address(cBank)))) {
        return cBank.advice(amount, direction, id);
      }
      // }
    }
    return false;
  }


  // Note that this function can become an external library based code that can be changed on the fly by the back office
  // function _shouldPlaceInPending(ISoCashAccount from, ISoCashAccount to, TransferInfo storage t, ActionType /*action*/) internal returns (bool) {
  //   // using the status to determine if it is a new transaction or a pending that is retested
  //   if (t.status != TransferStatus.NEW) return false;
  //   bool result = false;
  //   if (SharedFunctions.notNullAccount(from)) {
  //     AccountData storage ad = _accounts[from];

  //     // disable funds movement on inactive accounts
  //     if (!ad.active) {
  //       t.reason = string(abi.encodePacked(t.reason, result?", ":"", "Inactive sender account"));
  //       result = true;
  //     }
      
  //     // other conditions on sender here
  //   }
  //   if (SharedFunctions.notNullAccount(to)) {
  //     AccountData storage ad = _accounts[to];
  //     // disable funds movement on inactive accounts
  //     if (!ad.active) {
  //       t.reason = string(abi.encodePacked(result?", ":"", "Inactive recipient account"));
  //       result = true;
  //     }      
  //     // other conditions on recipient here
  //   }
  //   return result;
  // }

  // moved to the library
  // function _editBalance(ISoCashAccount account, uint256 _credit, uint256 _debit, uint256 _addLock, uint256 _delLock) internal {
  //   // Will proceed to the balance adjustment taking into account overdraft and locked balance
  //   // No event is generated here, it is just consistency function for the 3 fields of the account data
  //   // The consistency between the 3 fields is
  //   // real balance: balance - overdraft
  //   // locked funds cannot be spent. Locking/unlocking cannot change the balance
  //   // cannot lock more than the positive cash: balance >= locked
  //   // No overdraft if unlocked balance is positive: balance - locked > 0 => overdraft = 0
  //   // No unlocked balance if overdraft is positive: overdraft > 0 => balance - locked = 0
  //   // locking an insufficient balance will create overdraft and put it in the balance
  //   // unlocking when there is overdraft will release overdraft using the positive balance


  //   AccountData storage ad = _accounts[account];

  //   if (_credit>0) {
  //     // add credit, reducing the overdraft first
  //     uint amt = _credit;
  //     if (ad.overdraftBalance >= amt) {
  //       unchecked {
  //         ad.overdraftBalance -= amt;
  //         amt = 0;
  //       }
  //     } if (ad.overdraftBalance>0) {
  //       unchecked {
  //         amt -= ad.overdraftBalance;
  //         ad.overdraftBalance = 0;
  //         ad.balance += amt;
  //         _totalSupply += amt;
  //       }
  //     } else { // no overdraft
  //       ad.balance += amt;
  //       _totalSupply += amt;
  //     }
  //   }

  //   if (_delLock > 0) {
  //     // decrease the locked balance
  //     require(ad.lockedBalance >= _delLock, "SoC: Insufficient locked funds");
  //     unchecked {
  //       ad.lockedBalance -= _delLock;
  //     }
  //     // try release overdraft with balance 
  //     if (ad.overdraftBalance > 0) {
  //       if (ad.lockedBalance < ad.balance) {
  //         uint256 net = ad.balance - ad.lockedBalance;
  //         if (ad.overdraftBalance > net) {
  //           unchecked {
  //             ad.overdraftBalance -= net;
  //             ad.balance -= net;
  //             _totalSupply -= net;
  //           }
  //         } else {
  //           unchecked {
  //             ad.balance -= ad.overdraftBalance;
  //             _totalSupply -= ad.overdraftBalance;
  //             ad.overdraftBalance = 0;
  //           }
  //         }
  //       }
  //     }
  //   }

  //   if (_addLock > 0) {
  //     // increase the lock and eventually take from the overdraft limit if needed
  //     if(ad.balance > ad.lockedBalance+_addLock) {
  //       // we have enough free balance, just lock it
  //       ad.lockedBalance += _addLock;
  //     } else {
  //       // we do not have enough so we need to get it from the overdraft
  //       unchecked {
  //         uint256 missing = ad.lockedBalance+_addLock - ad.balance;
  //         ad.overdraftBalance += missing;
  //         ad.balance += missing;
  //         _totalSupply += missing;
  //         ad.lockedBalance += _addLock;
  //       }
  //     }
  //   } 

  
  //   if (_debit > 0 ) {
  //     // remove debit, take on overdraft only if needed and up to the limit
  //     unchecked {
  //       uint256 available = ad.balance - ad.lockedBalance;
  //       if (available >= _debit) {
  //         ad.balance -= _debit;
  //         _totalSupply -= _debit;
  //         _debit = 0;
  //       } else if (available > 0) {
  //         ad.balance -= available;
  //         _totalSupply -= available;
  //         _debit -= available;
  //         available = 0;
  //       }
  //       // _debit may have some balance left to use
  //       if (_debit>0) {
  //         // debit should be taken from overdraft
  //         ad.overdraftBalance += _debit;
  //       }
  //     }
  //   }

  //   // check the overdraft limit after the uopdates
  //   int limit = SharedFunctions._ioa(account).getAttributeNum(OVERDRAFT_AMOUNT);
  //   if (limit > 0) {
  //     require(ad.overdraftBalance <= uint256(limit), _addLock>0?"SoC: Overdraft limit would be reached, cannot lock the amount":"SoC: Overdraft limit would be reached, cannot debit account");
  //   } else {
  //     require(ad.overdraftBalance == 0, _addLock>0?"SoC: Insufficient unlocked funds":"SoC: Insufficient funds");
  //   }
    
  // }

  // handle all cases in one function to create code optimization but not necessarilly gas optimization
  function _transferMintBurn(ActionType action, ISoCashAccount sender, ISoCashAccount recipient, uint256 amount, TransferId id) internal returns (bool){
    if (this.shouldPlaceInPending(_accounts, sender, recipient, _transferDetails[id], action)) {
      _setTransferStatus(id, TransferStatus.PENDING);
      return false;
    }
    if (SharedFunctions.notNullAccount(sender)) _totalSupply = this.editBalance(sender, _accounts[sender], _totalSupply, 0, amount, 0, 0);
    if (SharedFunctions.notNullAccount(recipient)) _totalSupply = this.editBalance(recipient, _accounts[recipient], _totalSupply, amount, 0, 0, 0);
    emit Transfer(address(sender), address(recipient), amount);
    emit TransferEx(sender, recipient, amount, id);
    _setTransferStatus(id, TransferStatus.STP);
    return true;
  }
  

  function _lock(ISoCashAccount account, uint256 amount) internal returns (bool){
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot lock funds of a null account");
    require(_accounts[account].registered, "SoC: Cannot lock funds of an unregistered account");
    
    _totalSupply = this.editBalance(account, _accounts[account], _totalSupply, 0, 0, amount, 0);
    return true;
  }

  function _unlock(ISoCashAccount account, uint256 amount) internal returns (bool){
    require(SharedFunctions.notNullAccount(account), "SoC: Cannot unlock funds of a null account");
    require(_accounts[account].registered, "SoC: Cannot unlock funds of an unregistered account");
    
    _totalSupply = this.editBalance(account, _accounts[account], _totalSupply, 0, 0, 0, amount);
    return true;
  }


}