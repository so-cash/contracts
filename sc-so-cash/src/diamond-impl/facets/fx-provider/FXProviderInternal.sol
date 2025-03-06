// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

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
  FXRate,
  FXExecutionPlan,
  CCY, BIC, IBAN,
  ZERO_ACCOUNT, ZERO_BANK
  } from "../../../intf/so-cash-types.sol";
import {
  ISoCashOwnedAccount
} from "../../../intf/so-cash-account.sol";
import {
  ISoCashFXProviderInternal,
  ISoCashBankIdentity
} from "../../../intf/so-cash-bank.sol";
import {SharedFunctions} from "../../libs/SharedFunctions.sol";
import {FXProviderStorage} from "./FXProviderStorage.sol";
import {BankCorrespondentInternal} from "../bank-correspondents/BankCorrespondentInternal.sol";

contract FXProviderInternal is ISoCashFXProviderInternal, BankCorrespondentInternal {
  function _setCurrencyAccount(CCY ccy, ISoCashAccount account) internal {
    FXProviderStorage.Layout storage l = FXProviderStorage.layout();
    l._accounts[ccy] = account;
    emit CurrencyAccountSet(ccy, account);
  }

  function _setFXRateSource(CCY , CCY , string memory source) internal {
    FXProviderStorage.Layout storage l = FXProviderStorage.layout();
    l._fxRateSourceUrl = source;
  }
  function _getFXRateSource(CCY base, CCY quote) internal view returns (string memory) {
    FXProviderStorage.Layout storage l = FXProviderStorage.layout();
    return string(abi.encodePacked(l._fxRateSourceUrl,"?base=",base,"&quote=",quote));
  }

  function _setRateSigner(address signer) internal {
    FXProviderStorage.Layout storage l = FXProviderStorage.layout();
    l._rateSignerAddress = signer;
  }
  function _getRateSigner() internal view returns (address) {
    FXProviderStorage.Layout storage l = FXProviderStorage.layout();
    return l._rateSignerAddress;
  }

  function _hashOfFXRate(FXRate memory rate) internal view returns (bytes32) {
    // we integrate the tx.orgigin to ensure that the caller of the settlement function is the one that signed the rate
    return keccak256(abi.encodePacked(tx.origin, rate.base, rate.quote, rate.rate, rate.rateTime, rate.expiryTime));
  }

  function _getSignerOfSignature(bytes32 hash, bytes memory signature) internal pure returns (address) {
    // check the size of the signature
      require(signature.length == 65, "Invalid signature length, 65 expected");

      bytes32 r;
      bytes32 s;
      uint8 v;

      assembly {
          r := mload(add(signature, 32))
          s := mload(add(signature, 64))
          v := byte(0, mload(add(signature, 96)))
      }
      // the ecrecover function expect an ethereum v value (27 or 28)
      // but as this is a signature for something else it does not have the +27, but 0 or 1
      return ecrecover(hash, v<27?v+27:v, r, s);
  }

  function _recoverAddress(FXRate memory rate, bytes memory signature) internal view returns (address) {
    // check the signer is present
    
    bytes32 hash = _hashOfFXRate(rate);

    address signer = _getSignerOfSignature(hash, signature);
    return signer;
  }

  function _verifyFXRateHash(bytes32 hashOfRate, bytes memory signature) internal view returns (bool) {
    FXProviderStorage.Layout storage l = FXProviderStorage.layout();
    // check the signer is present
    require(l._rateSignerAddress != address(0), "Rate signer not set");
    
    address signer = _getSignerOfSignature(hashOfRate, signature);
    return signer == l._rateSignerAddress;
  }


  function _fxExecutionPlan(
    RecipentInfo memory from, 
    RecipentInfo memory to,
    CCY fromCcy, CCY toCcy
  ) internal view returns (FXExecutionPlan memory plan) {
    FXProviderStorage.Layout storage l = FXProviderStorage.layout();
    //  First get the payer account
    (, plan.debitFromAccount) = _getSoCashAccountOfRecipient(from);
    // then get the Fx Provider Beneficiary account
    plan.creditFxProviderAccount = l._accounts[fromCcy];

    // The get the FX Provider Source account
    plan.debitFxProviderAccount = l._accounts[toCcy];

    // then get the beneficiary account
    (, plan.creditToAccount) = _getSoCashAccountOfRecipient(to);
  }

  // the function can be called by anyone, but the signature must be valid
  // also, the debit from the from account implies that the account owner has allowed the transfer
  function _settlement(RecipentInfo memory from, RecipentInfo memory to, uint256 amount, FXRate memory rate, bytes memory signature, string memory details) internal returns (bool) {
    FXProviderStorage.Layout storage l = FXProviderStorage.layout();
    // check the signature
    bytes32 hash = _hashOfFXRate(rate);
    require(_verifyFXRateHash(hash, signature), "Invalid signature");
    require(l._rateUsedByOrigin[hash] == address(0), "Rate already used by a caller");

    // check the rate is still valid
    require(rate.expiryTime > block.timestamp, "Rate expired");

    // check the amount is positive
    require(amount > 0, "Amount must be positive");

    // check the rate is positive
    require(rate.rate > 0, "Rate must be positive");

    // get the accounts plan
    FXExecutionPlan memory plan = _fxExecutionPlan(from, to, rate.base, rate.quote);

    // check the plan is valid
    require(SharedFunctions.notNullAccount(plan.debitFromAccount), "FX: Debit account not set");
    require(SharedFunctions.notNullAccount(plan.creditFxProviderAccount), "FX: Credit FX account not set");
    require(SharedFunctions.notNullAccount(plan.debitFxProviderAccount), "FX: Debit FX account not set");
    require(SharedFunctions.notNullAccount(plan.creditToAccount), "FX: Credit account not set");

    // calculate the amount to be credited in the quote currency
    uint256 quoteAmount = amount * rate.rate / 10_000;

    // verify that the caller is allowed to act on the debit account
    require(SharedFunctions._iaw(plan.debitFromAccount).isWhitelisted(msg.sender), "Not allowed to act on the debit account");


    // store the use of the fxRate for preventing reuse (done before to prevent reentrancy)
    l._rateUsedByOrigin[hash] = tx.origin;

    // now perform the transfer
    bool success = SharedFunctions._ioa(plan.debitFromAccount).transferEx(RecipentInfo(plan.creditFxProviderAccount, BIC.wrap(0), IBAN.wrap(0)), amount, details);
    success = success && SharedFunctions._ioa(plan.debitFxProviderAccount).transferEx(RecipentInfo(plan.creditToAccount, BIC.wrap(0), IBAN.wrap(0)), quoteAmount, details);

    return success;
  }
}