// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "../intf/so-cash-types.sol";
import "../intf/so-cash-bank.sol";
import "../intf/so-cash-account.sol";
import "../utilities/whitelisted-senders.sol";
import "./payment-engine.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISoCashGlobalReferential, ISoCashCountryReferential, BankIdentifier, CodeType} from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";

import "../utilities/shared-lib.sol";


contract SoCashFXProvider is ISoCashFXProvider, WhitelistedSenders {
  string public constant version = "1.0.0";
  //#region STORAGE VARIABLES
  ISoCashGlobalReferential private _routingRef; // set by the methof setRouterReferential
  string private _fxRateSourceUrl;
 
  using PaymentEngine for SoCashFXProvider;
  // using IBANCalculator for SoCashBank;
  using SharedFunctions for *;

  mapping (CCY => ISoCashAccount) private _accounts;
  // FXRate sources is not implemented yet
  address private _rateSignerAddress; // will be needed to verify the signature of the FX Rate

  constructor(ISoCashGlobalReferential routingRef, address rateSigner) {
    _routingRef = routingRef;
    _rateSignerAddress = rateSigner;
    _fxRateSourceUrl = "unset";
  }

  function setCurrencyAccount(CCY ccy, ISoCashAccount account) public onlyWhitelisted {
    _accounts[ccy] = account;
    emit CurrencyAccountSet(ccy, account);
  }

  function setFXRateSource(CCY , CCY , string calldata source) public onlyWhitelisted {
    _fxRateSourceUrl = source;
  }
  function getFXRateSource(CCY base, CCY quote) public view returns (string memory) {
    return string(abi.encodePacked(_fxRateSourceUrl,"?base=",base,"&quote=",quote));
  }

  function setRateSigner(address signer) public onlyWhitelisted {
    _rateSignerAddress = signer;
  }
  function getRateSigner() public view returns (address) {
    return _rateSignerAddress;
  }

  function hashOfFXRate(FXRate memory rate) public view returns (bytes32) {
    // we integrate the tx.orgigin to ensure that the caller of the settlement function is the one that signed the rate
    return keccak256(abi.encodePacked(tx.origin, rate.base, rate.quote, rate.rate, rate.rateTime, rate.expiryTime));
  }

  function getSignerOfSignature(bytes32 hash, bytes memory signature) public pure returns (address) {
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

  function recoverAddress(FXRate memory rate, bytes memory signature) public view returns (address) {
    // check the signer is present
    require(_rateSignerAddress != address(0), "Rate signer not set");
    
    bytes32 hash = hashOfFXRate(rate);

    address signer = getSignerOfSignature(hash, signature);
    return signer;
  }

  function verifyFXRate(FXRate memory rate, bytes memory signature) public view returns (bool) {
    // check the signer is present
    require(_rateSignerAddress != address(0), "Rate signer not set");
    
    bytes32 hash = hashOfFXRate(rate);

    address signer = getSignerOfSignature(hash, signature);
    return signer == _rateSignerAddress;
  }

  // the function can be called by anyone, but the signature must be valid
  // also, the debit from the from account implies that the account owner has allowed the transfer
  function settlement(RecipentInfo calldata from, RecipentInfo calldata to, uint256 amount, FXRate calldata rate, bytes calldata signature, string calldata details) public returns (bool) {
    // check the signature
    require(verifyFXRate(rate, signature), "Invalid signature");

    // check the rate is still valid
    require(rate.expiryTime > block.timestamp, "Rate expired");

    // check the amount is positive
    require(amount > 0, "Amount must be positive");

    // check the rate is positive
    require(rate.rate > 0, "Rate must be positive");

    // get the accounts plan
    FXExecutionPlan memory plan = this.fxExecutionPlan(_routingRef, _accounts, from, to, rate.base, rate.quote);

    // check the plan is valid
    require(SharedFunctions.notNullAccount(plan.debitFromAccount), "FX: Debit account not set");
    require(SharedFunctions.notNullAccount(plan.creditFxProviderAccount), "FX: Credit FX account not set");
    require(SharedFunctions.notNullAccount(plan.debitFxProviderAccount), "FX: Debit FX account not set");
    require(SharedFunctions.notNullAccount(plan.creditToAccount), "FX: Credit account not set");

    // calculate the amount to be credited in the quote currency
    uint256 quoteAmount = amount * rate.rate / 10_000;

    // verify that the caller is allowed to act on the debit account
    require(SharedFunctions._iaw(plan.debitFromAccount).isWhitelisted(msg.sender), "Not allowed to act on the debit account");

    // now perform the transfer
    bool success = SharedFunctions._ioa(plan.debitFromAccount).transferEx(RecipentInfo(plan.creditFxProviderAccount, BIC.wrap(0), IBAN.wrap(0)), amount, details);
    success = success && SharedFunctions._ioa(plan.debitFxProviderAccount).transferEx(RecipentInfo(plan.creditToAccount, BIC.wrap(0), IBAN.wrap(0)), quoteAmount, details);

    return success;
  }


}