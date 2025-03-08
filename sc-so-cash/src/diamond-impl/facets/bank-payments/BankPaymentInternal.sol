// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {  IERC20 } from "@fever-tokens/diamond/src/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@fever-tokens/diamond/src/token/ERC20/extensions/IERC20Metadata.sol";
import {
  ISoCashGlobalReferential, 
  ISoCashCountryReferential,
  BankIdentifier
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {
  ISoCashBank,
  ISoCashAccount,
  RecipentInfo,
  NostroAccount,
  BankModel,
  OperationDirection,
  TransferId,
  TransferInfo,
  TransferStatus,
  BankAccount,
  ExecutionPlan,
  ActionType,
  CCY, BIC, IBAN,
  ZERO_ACCOUNT, ZERO_BANK
  } from "../../../intf/so-cash-types.sol";
import {
  ISoCashOwnedAccount
} from "../../../intf/so-cash-account.sol";
import {
  ISoCashBankPaymentInternal,
  ISoCashBankExplainPlan,
  ISoCashBankExternal,
  ISoCashBankIdentity
} from "../../../intf/so-cash-bank.sol";
import {SharedFunctions} from "../../libs/SharedFunctions.sol";

import {BankCorrespondentInternal} from "../bank-correspondents/BankCorrespondentInternal.sol";
import {BankNostroManagementInternal} from "../bank-nostros-mgmt/BankNostroManagementInternal.sol";
import {BankTransferManagementInternal} from "../bank-transfers-mgmt/BankTransferManagementInternal.sol";

contract BankPaymentInternal is ISoCashBankPaymentInternal, ISoCashBankExplainPlan, BankCorrespondentInternal, BankNostroManagementInternal, BankTransferManagementInternal {
  function ZERO_BANK_ACCOUNT() internal pure returns (BankAccount memory) {
      return BankAccount(BankModel.UNDEFINED, address(0), address(0));
  }
  function _planViaCorrespondentLogic(
    ISoCashAccount sender, // can be ZERO_ACCOUNT
    // RecipentInfo memory to, 
    uint256 amount, 
    TransferId id, 
    BankIdentifier memory target, 
    ISoCashBank onchainTarget) internal view returns (ExecutionPlan memory) {
    // sender can be null, in which case we act as pure intermediary
    // identify the correspondent bank that can be different from the target bank
    BankAccount memory ssi;
    (, onchainTarget, ssi) = _resolveCorrespondentBank(target, onchainTarget);

    // The target bank has a target bank account where it wants to be paid. 
    // Could be an account with us or an account elsewhere, including an ERC20.
    // If we have an account with that target bank and we have enough funds (or a credit line) we may prefer to use it
    // Else we have to credit the account of the target bank from a nostro at that same bank/ERC20 

    // get the nostro for the target bank if any
    NostroAccount storage nostro = _getNostro(address(onchainTarget), address(0)); 

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
    if (ssi.bank == address(this)) {
      // the ssi account is with us, we can credit it as new liability, so the only liquidity limit is the regulatory LCR.
      // We may need a size limit here to avoid too big transfers
      return ExecutionPlan(id, sender, ISoCashAccount(ssi.account), ZERO_ACCOUNT, onchainTarget, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
    } else if (ssi.model == BankModel.ERC20) {
      // They have an SSI that is an ERC20, check that we have a nostro in the same token
      // if so, we can use it to credit the correspondent bank
      NostroAccount memory nostroERC = _getNostro(ssi.bank, address(0));
      // We should check that the nostro exists or that the token has balance with the address of this smart contract
      // If we do not have liquidity on this token, then we should fail because we won't be able to transfer 
      IERC20 token = IERC20(ssi.bank);
      // If no nostro is defined, use this as the address
      if (nostroERC.model == BankModel.UNDEFINED) nostroERC = NostroAccount(BankModel.ERC20, ssi.bank, address(this), 0, 0, 0);
      // Get the current available balance in the token
      nostroERC.lastBalance = int256(token.balanceOf(nostroERC.account));

      require(uint256(nostroERC.lastBalance) >= amount, "SoC PE: No liquidity available in the ERC20 token");
      return ExecutionPlan(id, sender, ZERO_ACCOUNT, ZERO_ACCOUNT, onchainTarget, BankAccount(nostroERC.model, nostroERC.bank, nostroERC.account), ssi);
    
    } else if (ssi.model == BankModel.SO_CASH) {
      // They have an SSI acount we need to pay to, lets pay from our own ssi for this currency
      BankIdentifier memory selfId = _bankIdentifier();
      ISoCashCountryReferential country = _getCountryRef(selfId.country);
      BankAccount memory selfSSI = country.getSSI(selfId.codes, CCY.unwrap(_ccy()));

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


  function _transferExecutionPlan(
    ISoCashAccount sender, 
    RecipentInfo memory to, 
    uint256 amount, 
    TransferId id) internal view returns (ExecutionPlan memory) {
    require(SharedFunctions.notNullAccount(sender), "SoC: Cannot transfer from a null account");
    // ATTENTION: The creditLocalAccount of the plan may be forced to be self, to detect that it is a transfer out of an external nostro
    ISoCashAccount FAKE_ZERO_ACCOUNT = ISoCashAccount(address(this));
    
    // first check who's the beneficiary's bank
    (BankIdentifier memory target, ISoCashBank onchain, ISoCashAccount toAccount) = _getTargetBankIdentifier(to);
    // We have a bank identifier (country and codes, a target bank address and possibly an account address)
    if (onchain == ISoCashBank(address(this))) {
      // This is the beneficiary's bank: local transfer expected 
      if (SharedFunctions.notNullAccount(toAccount)) {
          return ExecutionPlan(id, sender, toAccount, ZERO_ACCOUNT, ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
      } else {
        // we are local but no target account: we burn. Case where the BIC was this bic and no IBAN was provided or the IBAN was not resolved
        return ExecutionPlan(id, sender, FAKE_ZERO_ACCOUNT, ZERO_ACCOUNT, ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
      }
    } else {
      require (SharedFunctions.sameCurrencyAndDecimals(
        IERC20Metadata(address(onchain)), 
        IERC20Metadata(address(this))), 
      "SoC: Currency mismatch");
      return _planViaCorrespondentLogic(sender, amount, id, target, onchain);
    }

  }


  function _interbankExecutionPlan(
    ISoCashBank senderBank, 
    RecipentInfo memory to, 
    uint256 amount, 
    TransferId id) internal view returns (ExecutionPlan memory plan) {
    
    // ATTENTION: The debitLocalAccount of the plan is force to be this, to detect that it is an interbank transfer
    ISoCashAccount FAKE_ZERO_ACCOUNT = ISoCashAccount(address(this));
    require(SharedFunctions.notNullBank(senderBank), "SoC: Cannot transfer from a null bank");
    // The control that our nostro with the sender bank has been credited is done in the interbankTransfer function
    // first check who's the beneficiary's bank
    (BankIdentifier memory target, ISoCashBank onchain, ISoCashAccount toAccount) = _getTargetBankIdentifier(to);
    if (onchain == ISoCashBank(address(this))) {
      // This is the beneficiary's bank: local transfer expected (TODO: optimisation, the account could be null so the if is not needed)
      if (SharedFunctions.notNullAccount(toAccount)) {
        // the recipient is an account here
        return ExecutionPlan(id, FAKE_ZERO_ACCOUNT, toAccount, ZERO_ACCOUNT, ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
      } else {
        // the recipient is the bank itself, we have received the funds on our nostro, so nothing to do
        return ExecutionPlan(id, FAKE_ZERO_ACCOUNT, ZERO_ACCOUNT, ZERO_ACCOUNT, ZERO_BANK, ZERO_BANK_ACCOUNT(), ZERO_BANK_ACCOUNT());
      }
    } else {
      plan = _planViaCorrespondentLogic(ZERO_ACCOUNT, amount, id, target, onchain);
      plan.debitLocalAccount = FAKE_ZERO_ACCOUNT;
    }
  }


  function _executePlan(TransferId id, ExecutionPlan memory plan) internal returns (bool) {
    TransferInfo memory ti = _transferInfo(id);
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
        NostroAccount storage nostro = _getNostro(plan.payViaAccount.bank, plan.payViaAccount.account);
        if (plan.payViaAccount.model == BankModel.SO_CASH) {
          success = success && ISoCashOwnedAccount(plan.payViaAccount.account).transferEx(
            RecipentInfo(ISoCashAccount(plan.payToAccount.account), BIC.wrap(0), IBAN.wrap(0)), ti.amount, ti.details);
          controlConsistency++; // we have debited our nostro, so reduced our asset, so like increase our liability
        } else if (plan.payViaAccount.model == BankModel.ERC20) {
          if (plan.payViaAccount.account == address(this)) {
            // require(false, "debug: payviaaccount is this bank");
            // Here the source account is this smart contract so we can call transfer directly
            success = success && IERC20(plan.payViaAccount.bank).transfer(plan.payToAccount.account, ti.amount);
            controlConsistency++; // we have debited our ERC20 nostro, so reduced our asset, so like increase our liability
          } else {
            // require(false, "debug: payviaaccount is not this bank");
            // Here the source account is another address that should have approved this contract to transfer on its behalf
            success = success && IERC20(plan.payViaAccount.bank).transferFrom(plan.payViaAccount.account, plan.payToAccount.account, ti.amount);
            controlConsistency++; // we have debited our nostro, so reduced our asset, so like increase our liability
          }
        }
        nostro.lastBalance = _getNostroBalanceByModel(nostro.model, nostro.bank, nostro.account);
        success = success && SharedFunctions._ibi(plan.payViaBank).interbankTransfer(
          plan.payToAccount, ti.recipient, ti.amount, id);
      }
    }

    require(controlConsistency == 0, "SoC: Inconsistent execution plan");
    return success;
  }

  function _transferLogic(ISoCashAccount sender, RecipentInfo memory to, uint256 amount, TransferId id) internal returns (bool) {

    ExecutionPlan memory plan = _transferExecutionPlan(sender, to, amount, id);
    emit ExplainPlan(plan);
    return _executePlan(id, plan);
  }

  function _interbankTransferLogic(ISoCashBank senderBank, RecipentInfo memory to, uint256 amount, TransferId id) internal returns (bool) {

    ExecutionPlan memory plan = _interbankExecutionPlan(senderBank, to, amount, id);
    emit ExplainPlan(plan);
    return _executePlan(id, plan);
  }

  function _requestNetting(ISoCashBank cBank, ISoCashAccount loro, uint256 amount) internal returns (bool) {
    require(SharedFunctions.notNullBank(cBank), "SoC: Cannot request netting with a null correspondent bank");
    NostroAccount storage nostro = _getNostro(address(cBank), address(0));
    require(nostro.model == BankModel.SO_CASH, "SoC: The bank does not have a so-cash nostro account for you");
    require(_isRegistered(loro), "SoC: Cannot request netting with an invalid loro account");

    require(_unlockedBalanceOf(loro) >= amount, "SoC: Insufficient funds for netting");
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
    success = success && _checkNostroBalanceAdjusted(BankAccount(BankModel.SO_CASH, nostro.bank, nostro.account), - int256(amount));
    return success;
  }

  function _interbankNetting(ISoCashBank correspondentBank, uint256 amount, TransferId id) internal returns (bool) {
    NostroAccount storage nostro = _getNostro(address(correspondentBank), address(0));
    require(nostro.model == BankModel.SO_CASH, "SoC: Netting only supported for so-cash accounts");
    TransferInfo memory info = ISoCashBankExternal(msg.sender).transferInfo(id);
    ISoCashAccount loro = info.recipient.account;
    require(_isRegistered(loro), "SoC: Netting account not registered");
    // create a transfer info from a copy of the recipient info
    // This is a specific case where we need to invert the sender and recipient
    TransferId localId = _createTransferInfo(
      loro, 
      RecipentInfo(ISoCashAccount(nostro.account), BIC.wrap(0), IBAN.wrap(0)), 
      amount, "Netting request");

    // check that our nostro has been debited
    _checkNostroBalanceAdjusted(BankAccount(BankModel.SO_CASH, nostro.bank, nostro.account), - int256(amount));

    bool success = _transferMintBurn(ActionType.BURN, loro, ZERO_ACCOUNT, amount, localId);
    return success;
  }

  function _interbankTransfer(ISoCashBankExternal srcBank, BankAccount memory ssi, RecipentInfo memory to, uint256 amount, TransferId id) internal returns (bool) {
    // create a transfer info from a copy of the recipient info
    TransferId localId = _copyTransferInfo(srcBank.transferInfo(id));

    // check that the ssi that was used by the calling bank is actually a nostro at our level
    _checkNostroBalanceAdjusted(ssi, int256(amount));

    return _interbankTransferLogic(ISoCashBank(address(srcBank)), to, amount, localId);
  }

  function _transfer(ISoCashAccount from, RecipentInfo memory to, uint256 amount, string memory details) internal returns (bool) {
    TransferId id = _createTransferInfo(from, to, amount, details);
    return _transferLogic(from, to, amount, id);
  }

  function _advice(ISoCashBankExternal srcBank, uint256 amount, OperationDirection direction, TransferId id) internal returns (bool) {
    NostroAccount storage nostro = _getNostro(address(srcBank), address(0));
    // If the nostro does not exist for the caller we should reject the call
    if (_adviceNostro(address(srcBank), amount, direction, id)) {
      emit Adviced(ISoCashBank(address(this)), ISoCashAccount(nostro.account), amount, direction, id);
      return true; 
    } else return false; // because there was no nostro for the caller
  }


  function _decidePendingTransfer(TransferId id, TransferStatus status, string memory reason) internal returns (bool) {
    TransferInfo memory ti = _transferInfo(id);
    require(ti.status == TransferStatus.PENDING, "SoC: The transfer is not pending");
    require(status == TransferStatus.CANCELLED || status == TransferStatus.PROCESSED, "SoC: Invalid status");
    
    ti.reason = SharedFunctions._join(ti.reason, ", =>", reason);
    if (status == TransferStatus.CANCELLED) {
      // if the transfer is cancelled
      _setTransferStatus(id, TransferStatus.CANCELLED);
      return true;
    } 

    // Review the transaction to decide what operation to do
    if (SharedFunctions.notNullAccount(ti.sender)) {
      ISoCashBank srcBank = ISoCashBank(SharedFunctions.getBankOf(address(ti.sender)));
      // TODO: review if we can just call the transfer logic here
      if (srcBank == ISoCashBank(address(this))) {
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



}