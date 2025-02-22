// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;


import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../intf/so-cash-types.sol";
import "../intf/so-cash-account.sol";
import "../intf/so-cash-bank.sol";
import "../utilities/IBAN.sol";
import "../utilities/shared-lib.sol";
import {ISoCashGlobalReferential, ISoCashCountryReferential, BankIdentifier, CodeType} from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";

library PaymentEngine {
  using PaymentEngine for ISoCashBank;
  using IBANCalculator for ISoCashBank;
  function ZERO_BANK_ACCOUNT() internal pure returns (BankAccount memory) {
    return BankAccount(BankModel.UNDEFINED, address(0), address(0));
  }

// Function to cast bytes10 to bytes5
  function toBytes5(CodeType input) internal pure returns (bytes5) {
      return bytes5(CodeType.unwrap(input));
  }

  function ibanOfAccount(ISoCashBank , BankIdentifier storage _bankId, CCY _ccy, AccountNumber an) external view returns (string memory) {
    require(AccountNumber.unwrap(an) != 0, "SoC: Account not registered");
    // require(address(_ibanCalc) != address(0), "SoC: IBAN calculator not set");
    string memory country2 = string(abi.encodePacked(_bankId.country));
    string memory bankCode5 = string(abi.encodePacked(toBytes5(_bankId.codes[0])));
    string memory branchCode5 = string(abi.encodePacked(toBytes5(_bankId.codes[1])));
    string memory accountNumber11 = IBANCalculator.uintToString(AccountNumber.unwrap(an));
    bytes memory ccy = abi.encodePacked(_ccy);
    accountNumber11 = IBANCalculator.padWithZeros(accountNumber11, 8);
    accountNumber11 = string(abi.encodePacked(ccy[0], ccy[1], ccy[2], accountNumber11));
    string memory ibanStr = IBANCalculator.calculateFrenchIBAN(country2, bankCode5, branchCode5, accountNumber11);
    return ibanStr;
  }

  function decodeIBAN(string memory iban) external pure returns (BankIdentifier memory bankId, string memory account) {
    return decodeIBANInternal(iban);
  }
  function decodeIBANInternal(string memory iban) internal pure returns (BankIdentifier memory bankId, string memory account) {
    // bytes memory bytesIban = bytes(iban);
    // bankId.country = bytes2(bytesIban[1])>>8 | bytes2(bytesIban[0]);
    (bool valid, string memory country, string memory bankCode5, string memory branchCode5, string memory accountNumber11, ) 
      = IBANCalculator.extractFrenchIBAN(iban);
    require(valid, "SoC: Invalid IBAN");

    bankId.codes = new CodeType[](2);
    account = accountNumber11;
    // create the bank identifier
    bankId.country = bytes2(bytes(country)[1])>>8 | bytes2(bytes(country)[0]);
    bankId.codes[0] = CodeType.wrap(bytes5(bytes32(bytes(bankCode5))));
    bankId.codes[1] = CodeType.wrap(bytes5(bytes32(bytes(branchCode5))));
  }

  function decodeIBANIntoBankAccount(ISoCashBank, ISoCashGlobalReferential _routingRef, string memory iban) external view returns (BankAccount memory) {
    BankIdentifier memory bankId;
    string memory accountNumber11;
    (bankId, accountNumber11) = decodeIBANInternal(iban);
    ISoCashCountryReferential country = _routingRef.getCountry(bankId.country);
    require(address(country) != address(0), "SoC PE: Country not found in the referential");

    bytes memory accountBytes = bytes(accountNumber11);
    bytes3 ccy3 = bytes3(accountBytes[0]) | (bytes3(accountBytes[1]) >> 8) | (bytes3(accountBytes[2]) >> 16);
    address bank = address(country.getBankModule(bankId.codes, ccy3));
    require(bank != address(0), "SoC PE: Bank not found in the referential");
    address account = address(SharedFunctions._ibe(ISoCashBank(bank)).addressOfFullAccount(accountNumber11));
    return BankAccount(BankModel.SO_CASH, bank, account);
  }


  function getNostroBalanceByModel(BankModel model, address bank, address account) internal view returns (int256 actual) {
    if (bank == address(0)) return 0;
    if (model == BankModel.SO_CASH) {
      actual = ISoCashBankExternal(bank).fullBalanceOf(ISoCashAccount(account));
    } else if (model == BankModel.ERC20) {
      actual = int256(IERC20Metadata(bank).balanceOf(account));
    } else {
      actual = 0;
    }
  }

  function adviceNostro(ISoCashBank , 
    NostroAccount storage nostro, 
    uint256 amount, OperationDirection direction, TransferId ) external returns (bool) {
    if (nostro.model != BankModel.SO_CASH) return false;
    int256 balance = PaymentEngine.getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);

    if (direction == OperationDirection.CREDIT) {
      nostro.lastAdviceAmount = int256(amount);
      require(nostro.lastBalance + int256(amount) == balance, "SoC: Our nostro has not been credited according to advice");
    } else {
      nostro.lastAdviceAmount = -int256(amount);
      require(nostro.lastBalance == balance + int256(amount), "SoC: Our nostro has not been debited according to advice");
    }
    nostro.lastBalance = balance;
    nostro.lastBlock = block.number;
    return true;
  }

  function checkNostroBalanceAdjusted(ISoCashBank , 
    mapping(address => NostroAccount) storage _nostros,
    BankAccount memory ssi, int256 amount) external returns (bool) {
    // check that the nostro at bank that was used by the calling bank is actually a nostro at our level
    NostroAccount storage nostro = _nostros[ssi.bank];
    require(nostro.account == ssi.account && nostro.model == ssi.model, "SoC: The account provided is not a nostro account");
    
    // We have 2 scenario to cover. One where the nostro has been updated via an Advise call, and one where it was not
    if (nostro.lastBlock == block.number) { // Advice was called, the balance is already updated
      require(nostro.lastAdviceAmount == amount, "SoC: Our nostro has not been credited of the right amount");
    } else {
      // check that our nostro has been updated and update it locally
      int256 balance = PaymentEngine.getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);
      require(nostro.lastBalance + amount == balance, "SoC: Our nostro not been updated according to the amount");
      nostro.lastBalance = balance;
      nostro.lastBlock = block.number;
      nostro.lastAdviceAmount = amount;
    }
    
    return true;
  }

  function shouldPlaceInPending(ISoCashBank ,
    mapping(ISoCashAccount => AccountData) storage _accounts,
    ISoCashAccount from, ISoCashAccount to, TransferInfo storage t, ActionType /*action*/) external returns (bool) {
    // using the status to determine if it is a new transaction or a pending that is retested
    if (t.status != TransferStatus.NEW) return false;
    bool result = false;
    if (SharedFunctions.notNullAccount(from)) {
      AccountData storage ad = _accounts[from];

      // disable funds movement on inactive accounts
      if (!ad.active) {
        t.reason = string(abi.encodePacked(t.reason, result?", ":"", "Inactive sender account"));
        result = true;
      }
      
      // other conditions on sender here
    }
    if (SharedFunctions.notNullAccount(to)) {
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

  function getSoCashAccountOfRecipient(
    ISoCashGlobalReferential _routingRef, 
    RecipentInfo memory recipient,
    CCY _ccy
  ) internal view returns (ISoCashBank bank, ISoCashAccount account) {
    if (SharedFunctions.notNullAccount(recipient.account)) {
      bank = SharedFunctions._ioa(recipient.account).bank();
      return ( bank, recipient.account);
    } else {
      bank = ZERO_BANK;
      account = ZERO_ACCOUNT;
      // need the IBAN to be specified
      if(IBAN.unwrap(recipient.iban) != 0) {
        string memory iban = string(abi.encodePacked(recipient.iban));
        string memory sAccount;
        BankIdentifier memory targetBank;
        // Extract the bank identifier from the IBAN and the account string
        (targetBank, sAccount) = decodeIBANInternal(iban);
        // Get from the referential the instance that contains the country referential
        ISoCashCountryReferential country = _routingRef.getCountry(targetBank.country);
        if (address(country) != address(0)) {
          // Get the smart contract from the referential that match this bank identifier and currency
          bank = ISoCashBank(address(country.getBankModule(targetBank.codes, CCY.unwrap(_ccy))));
          // Try getting the account from the bank instance
          if (SharedFunctions.notNullBank(bank)) {
            account = SharedFunctions._ibe(bank).addressOfFullAccount(sAccount);
          } 
        } 
      }
      // In all other cases, the bank and account are zeroed
    }
  }
  /**
  * Returns the BankIdentifier (codes and country) of the target bank and the onchain instance of the bank and the account if it is local
   */
  function getTargetBankIdentifier(
    ISoCashBank self, 
    ISoCashGlobalReferential _routingRef, 
    RecipentInfo memory recipient) internal view returns (BankIdentifier memory targetBank, ISoCashBank onchain, ISoCashAccount account) {
    // If the recipient is an eth address we get the bank from it as if the address is an account
    if (SharedFunctions.notNullAccount(recipient.account)) {
      require(SharedFunctions.sameCurrencyAndDecimals(SharedFunctions._ioa(recipient.account), IERC20Metadata(address(this))), "SoC: Expect the recipient to have the same currency and decimals as the bank");
      ISoCashBank bank = SharedFunctions._ioa(recipient.account).bank();
      return (SharedFunctions._ibe(bank).bankIdentifier(), bank, recipient.account);
    } else {
      // need the IBAN to be specified
      if(IBAN.unwrap(recipient.iban) != 0) {
        string memory iban = string(abi.encodePacked(recipient.iban));
        string memory sAccount;
        // Extract the bank identifier from the IBAN and the account string
        (targetBank, sAccount) = decodeIBANInternal(iban);
        // Get from the referential the instance that contains the country referential
        ISoCashCountryReferential country = _routingRef.getCountry(targetBank.country);
        if (address(country) != address(0)) {
          // Get the smart contract from the referential that match this bank identifier and currency
          CCY _ccy = CCY.wrap(bytes3(bytes(SharedFunctions._ierc(self).symbol())));
          ISoCashBank bank = ISoCashBank(address(country.getBankModule(targetBank.codes, CCY.unwrap(_ccy))));
          // Try getting the account from the bank instance
          if (SharedFunctions.notNullBank(bank)) {
            account = SharedFunctions._ibe(bank).addressOfFullAccount(sAccount);
            require(SharedFunctions.notNullAccount(account), "SoC PE: Target account not found in the bank");
          }
          return (targetBank, bank, account);
        } else {
          require(false, "SoC PE: Country not found in the referential");
        }
      } else {
        // The IBAN was not specified, we should have a BIC
        if (BIC.unwrap(recipient.bic) != 0) {
          // only a BIC has been specified, this cannot be handled properly for now 
          // TODO: We would need to add the BIC in the referential 
          // check that it is our BIC
          BIC _bic = BIC.wrap(bytes11(bytes(SharedFunctions._ibe(self).bic())));
          if (BIC.unwrap(_bic) == BIC.unwrap(recipient.bic)) {
            // return as if we need to transfer to zero (burn the balance)
            return (SharedFunctions._ibe(self).bankIdentifier(), self, ZERO_ACCOUNT);
          } else {
            // we need to find the bank from the BIC
            require(false, "SoC: BIC not supported yet");
          }
        }
      }
    }
    // The default return is a zeroed value
  }

  /**
    Returns the next bank to reach the target bank and the correspondent bank if it exists
    Provides the BankIdentifier and if available its onchain address and the actual local correspondent bank record
   */
  function resolveCorrespondentBank(
    ISoCashBank self, 
    ISoCashGlobalReferential _routingRef, 
    BankIdentifier memory targetBank, 
    ISoCashBank targetOnchain) internal view returns (BankIdentifier memory id, ISoCashBank onchain, BankAccount memory ssi) {
    
    BankIdentifier memory selfId = SharedFunctions._ibe(self).bankIdentifier();
    bytes3 _ccy = bytes3(bytes(SharedFunctions._ierc(self).symbol()));
    ISoCashCountryReferential country = _routingRef.getCountry(selfId.country);
    require(address(country) != address(0), "SoC PE: Country not found in the referential");
    
    // If we target ourself (should not happen but added for consistency)
    if (targetOnchain == self) return (targetBank, self, BankAccount( BankModel.UNDEFINED, address(0), address(0)) ); 
    
    // First look locally if the target bank is a correspondent
    if (country.isCorrespondent(selfId.codes, _ccy, targetBank)) { // target bank is a correspondent so this is the next bank
      country = _routingRef.getCountry(targetBank.country);
      BankAccount memory account = country.getSSI(targetBank.codes, _ccy);
      return (targetBank, targetOnchain, account);
    } else {
      // The target bank is not a correspondent, we need to find a route to it using the referential
      require(address(_routingRef) != address(0), "SoC: Route referential not defined");
      
      (bool resolved, BankIdentifier[] memory route) = _routingRef.resolveRoute(_ccy, selfId, targetBank);
      if (resolved && route.length>=2) {
        // the first of the route is us
        // the second is a correspondent bank, no need to control because the referential is the golden source
        country = _routingRef.getCountry(route[1].country);
        ISoCashBank bank = ISoCashBank(address(country.getBankModule(route[1].codes, _ccy)));
        BankAccount memory account = country.getSSI(route[1].codes, _ccy);
        return (route[1], bank, account);
      }
    }
    require(false, "SoC PE: Could not find a route to the target bank");
  }

  function planViaCorrespondentLogic(ISoCashBank self, 
    mapping(address => NostroAccount) storage _nostros,
    // IBANCalculator _ibanCalc, 
    ISoCashGlobalReferential _routingRef, 
    ISoCashAccount sender, // can be ZERO_ACCOUNT
    // RecipentInfo memory to, 
    uint256 amount, 
    TransferId id, 
    BankIdentifier memory target, 
    ISoCashBank onchainTarget) internal view returns (ExecutionPlan memory) {
    // sender can be null, in which case we act as pure intermediary
    // identify the correspondent bank that can be different from the target bank
    BankAccount memory ssi;
    (, onchainTarget, ssi) = PaymentEngine.resolveCorrespondentBank(self, _routingRef, target, onchainTarget);

    // The target bank has a target bank account where it wants to be paid. 
    // Could be an account with us or an account elsewhere, including an ERC20.
    // If we have an account with that target bank and we have enough funds (or a credit line) we may prefer to use it
    // Else we have to credit the account of the target bank from a nostro at that same bank/ERC20 

    NostroAccount storage nostro = _nostros[address(onchainTarget)];

    if (nostro.model == BankModel.SO_CASH) { // we have a nostro account with this correspondent bank
      // 2 options: Credit the loro of the bank or use our funds in our nostro with them to credit the beneficiary
      if (uint256(nostro.lastBalance) >= amount) { // TODO: ideally we should be able to test also if we have a credit line here
        // we have enough funds in nostro
        // we can debit the client and credit the beneficiary
        return ExecutionPlan(id, sender, ZERO_ACCOUNT, ISoCashAccount(nostro.account), ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
      }
      // else we do not have liquidity in this account so we need to find another source of liqudity in our nostros
    }
    // then we prioritize the ssi of the correspondent bank
    // Test if the ssi account is with us
    if (ssi.bank == address(self)) {
      // the ssi account is with us, we can credit it as new liability, so the only liquidity limit is the regulatory LCR.
      // We may need a size limit here to avoid too big transfers
      return ExecutionPlan(id, sender, ISoCashAccount(ssi.account), ZERO_ACCOUNT, onchainTarget, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
    } else if (ssi.model == BankModel.ERC20) {
      // They have an SSI that is an ERC20, check that we have a nostro in the same token
      // if so, we can use it to credit the correspondent bank
      NostroAccount memory nostroERC = _nostros[ssi.bank];
      // We should check that the nostro exists or that the token has balance with the address of this smart contract
      // If we do not have liquidity on this token, then we should fail because we won't be able to transfer 
      IERC20 token = IERC20(ssi.bank);
      // If no nostro is defined, use self as the address
      if (nostroERC.model == BankModel.UNDEFINED) nostroERC = NostroAccount(BankModel.ERC20, ssi.bank, address(self), 0, 0, 0);
      // Get the current available balance in the token
      nostroERC.lastBalance = int256(token.balanceOf(nostroERC.account));
      require(uint256(nostroERC.lastBalance) >= amount, "SoC PE: No liquidity available in the ERC20 token");
      return ExecutionPlan(id, sender, ZERO_ACCOUNT, ZERO_ACCOUNT, onchainTarget, BankAccount(nostroERC.model, nostroERC.bank, nostroERC.account), ssi);
    } else if (ssi.model == BankModel.SO_CASH) {
      // They have an SSI acount we need to pay to, lets pay from our own ssi for this currency
      bytes3 _ccy = bytes3(bytes(SharedFunctions._ierc(self).symbol()));
      BankIdentifier memory selfId = SharedFunctions._ibe(self).bankIdentifier();
      ISoCashCountryReferential country = _routingRef.getCountry(selfId.country);
      BankAccount memory selfSSI = country.getSSI(selfId.codes, _ccy);
      if (selfSSI.model == BankModel.SO_CASH) {
        // we have an SSI account for the currency from which we can pay from
        // check we have enough balance, get the balance first then check
        int256 balance = ISoCashBankExternal(selfSSI.bank).fullBalanceOf(ISoCashAccount(selfSSI.account));
        require(uint256(balance) >= amount, "SoC PE: No liquidity available in the SSI");
        return ExecutionPlan(id, sender, ZERO_ACCOUNT, ZERO_ACCOUNT, onchainTarget, selfSSI, ssi);
      } else {
        require(false, "SoC PE: No matching SSI account found for the paying bank");
      }
      // // the loro account is not with us, we need to see if we have a nostro with that same bank
      // if (_nostros[ssi.bank].model != BankModel.UNDEFINED) {
      //   // TODO: control that the models are the same
      //   nostro = _nostros[ssi.bank];
      //   // we have a nostro with the same bank as the ssi account
      //   // we can use it to credit the correspondent bank
      // } else {
      //   // we don't have a nostro with the ssi bank, no solution possible for the moment
      //   // We should get the next correspondent for that bank and hopefully we have a nostro there or a nostro at the same bank
      //   // todo: where should the error be handled
      //   require(false, "SoC PE: Correspondent does not have a SSI");
      // }
    } else {
      require(false, "SoC PE: Correspondent does not have a SSI");
    }

    return ExecutionPlan(id, ZERO_ACCOUNT, ZERO_ACCOUNT, ZERO_ACCOUNT, ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
  }

  function transferExecutionPlan(
    ISoCashBank self, 
    mapping(address => NostroAccount) storage _nostros,
    ISoCashGlobalReferential _routingRef, 
    ISoCashAccount sender, 
    RecipentInfo memory to, 
    uint256 amount, 
    TransferId id) external view returns (ExecutionPlan memory) {
    require(SharedFunctions.notNullAccount(sender), "SoC: Cannot transfer from a null account");
    // ATTENTION: The creditLocalAccount of the plan may be forced to be self, to detect that it is a transfer our an external nostro
    ISoCashAccount FAKE_ZERO_ACCOUNT = ISoCashAccount(address(self));
    
    // first check who's the beneficiary's bank
    (BankIdentifier memory target, ISoCashBank onchain, ISoCashAccount toAccount) = self.getTargetBankIdentifier(_routingRef, to);
    // We have a bank identifier (country and codes, a target bank address and possibly an account address)
    if (onchain == self) {
      // This is the beneficiary's bank: local transfer expected (TODO: optimisation, the account could be null so the if is not needed)
      if (SharedFunctions.notNullAccount(toAccount)) {
          return ExecutionPlan(id, sender, toAccount, ZERO_ACCOUNT, ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
      } else {
        // we are local but no target account: we burn. Case where the BIC was this bic and no IBAN was provided or the IBAN was not resolved
        return ExecutionPlan(id, sender, FAKE_ZERO_ACCOUNT, ZERO_ACCOUNT, ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
      }
    } else {
      return PaymentEngine.planViaCorrespondentLogic(self, _nostros, _routingRef, sender, amount, id, target, onchain);
    }

  }

  function interbankExecutionPlan(
    ISoCashBank self, 
    mapping(address => NostroAccount) storage _nostros,
    ISoCashGlobalReferential _routingRef, 
    ISoCashBank senderBank, 
    RecipentInfo memory to, 
    uint256 amount, 
    TransferId id) external view returns (ExecutionPlan memory) {
    
    return PaymentEngine.interbankExecutionPlanInternal(self, _nostros, _routingRef, senderBank, to, amount, id);
  }
    

  function interbankExecutionPlanInternal(
    ISoCashBank self, 
    mapping(address => NostroAccount) storage _nostros,
    ISoCashGlobalReferential _routingRef, 
    ISoCashBank senderBank, 
    RecipentInfo memory to, 
    uint256 amount, 
    TransferId id) internal view returns (ExecutionPlan memory plan) {
    
    // ATTENTION: The debitLocalAccount of the plan is force to be self, to detect that it is an interbank transfer
    ISoCashAccount FAKE_ZERO_ACCOUNT = ISoCashAccount(address(self));
    require(SharedFunctions.notNullBank(senderBank), "SoC: Cannot transfer from a null bank");
    // The control that our nostro with the sender bank has been credited is done in the interbankTransfer function
    // first check who's the beneficiary's bank
    (BankIdentifier memory target, ISoCashBank onchain, ISoCashAccount toAccount) = PaymentEngine.getTargetBankIdentifier(self, _routingRef, to);
    if (onchain == self) {
      // This is the beneficiary's bank: local transfer expected (TODO: optimisation, the account could be null so the if is not needed)
      if (SharedFunctions.notNullAccount(toAccount)) {
        // the recipient is an account here
        return ExecutionPlan(id, FAKE_ZERO_ACCOUNT, toAccount, ZERO_ACCOUNT, ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
      } else {
        // the recipient is the bank itself, we have received the funds on our nostro, so nothing to do
        return ExecutionPlan(id, FAKE_ZERO_ACCOUNT, ZERO_ACCOUNT, ZERO_ACCOUNT, ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
      }
    } else {
      plan = PaymentEngine.planViaCorrespondentLogic(self, _nostros, _routingRef, ZERO_ACCOUNT, amount, id, target, onchain);
      plan.debitLocalAccount = FAKE_ZERO_ACCOUNT;
    }
  }


  function fxExecutionPlan(
    ISoCashFXProvider ,
    ISoCashGlobalReferential _routingRef, 
    mapping(CCY => ISoCashAccount) storage _accounts,
    RecipentInfo memory from, 
    RecipentInfo memory to,
    CCY fromCcy, CCY toCcy
  ) external view returns (FXExecutionPlan memory plan) {
    //  First get the payer account
    (, plan.debitFromAccount) = getSoCashAccountOfRecipient(_routingRef, from, fromCcy);
    // then get the Fx Provider Beneficiary account
    plan.creditFxProviderAccount = _accounts[fromCcy];

    // The get the FX Provider Source account
    plan.debitFxProviderAccount = _accounts[toCcy];

    // then get the beneficiary account
    (, plan.creditToAccount) = getSoCashAccountOfRecipient(_routingRef, to, toCcy);
  }

  function decodeAccountNumber(
    ISoCashBank self, 
    string memory accountNumber11) external view returns (AccountNumber) {
      // extract the number from the string, account starts with the 3 letters of the currency
    bytes memory ccy3 = new bytes(3);
    for (uint i = 0; i < 3; i++) {
      ccy3[i] = bytes(accountNumber11)[i];
    } 
    // Make sure the currency is the same as the one we are using in this module
    string memory _ccy = SharedFunctions._ierc(self).symbol();
    
    require(SharedFunctions.strcmp(string(ccy3), _ccy), "SoC: Currency mismatch");
    bytes memory account8 = new bytes(8);
    for (uint i = 3; i < 11; i++) {
      account8[i - 3] = bytes(accountNumber11)[i];
    }
    uint256 num = IBANCalculator.frenchStringToNumber(string(abi.encodePacked(account8)));
    AccountNumber an = AccountNumber.wrap(uint32(num));
    return an;
  }

  function editBalance(ISoCashBank , ISoCashAccount account, AccountData storage ad, uint256 _totalSupply, uint256 _credit, uint256 _debit, uint256 _addLock, uint256 _delLock) external returns (uint256 newSupply) {
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


      // AccountData storage ad = _accounts[account];

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
      int limit = SharedFunctions._ioa(account).getAttributeNum(OVERDRAFT_AMOUNT);
      if (limit > 0) {
        require(ad.overdraftBalance <= uint256(limit), _addLock>0?"SoC: Overdraft limit would be reached, cannot lock the amount":"SoC: Overdraft limit would be reached, cannot debit account");
      } else {
        require(ad.overdraftBalance == 0, _addLock>0?"SoC: Insufficient unlocked funds":"SoC: Insufficient funds");
      }
      return _totalSupply;
  }
}

contract PaymentEngineTest {
  function decodeIBAN(string memory iban) external pure returns (BankIdentifier memory bankId, string memory account, bytes3 ccy) {
    (BankIdentifier memory id, string memory accountNumber11) = PaymentEngine.decodeIBANInternal(iban);
    bytes memory accountBytes = bytes(accountNumber11);
    bytes3 ccy3 = bytes3(accountBytes[0]) | (bytes3(accountBytes[1]) >> 8) | (bytes3(accountBytes[2]) >> 16);
    return (id, accountNumber11, ccy3);
  }
}