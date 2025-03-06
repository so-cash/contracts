// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;


import {ISoCashAccount, FXRate, RecipentInfo, CCY} from "../../../intf/so-cash-types.sol";
import {ISoCashFXProvider} from "../../../intf/so-cash-bank.sol";
import {FXProviderInternal} from "./FXProviderInternal.sol";
import {WhitelistedSendersInternal} from "../whitelisted-senders/WhitelistedSendersInternal.sol";

contract FXProvider is ISoCashFXProvider, FXProviderInternal, WhitelistedSendersInternal {

    function setCurrencyAccount(CCY ccy, ISoCashAccount account) external override onlyWhitelisted {
      _setCurrencyAccount(ccy, account);
    }

    function setFXRateSource(CCY base, CCY quote, string calldata source) external override onlyWhitelisted {
      _setFXRateSource(base, quote, source);
    }
    function getFXRateSource(CCY base, CCY quote) external view override returns (string memory) {
      return _getFXRateSource(base, quote);
    }

    function setRateSigner(address signer) external override onlyWhitelisted {
      _setRateSigner(signer);
    }
    function getRateSigner() external view override returns (address) {
      return _getRateSigner();
    }

    function hashOfFXRate(FXRate memory rate) external view override returns (bytes32) {
      return _hashOfFXRate(rate);
    }
    function verifyFXRate(FXRate memory rate, bytes memory signature) external view override returns (bool) {
      bytes32 hash = _hashOfFXRate(rate);
      return _verifyFXRateHash(hash, signature);
    }
    function settlement(
      RecipentInfo calldata from, 
      RecipentInfo calldata to, 
      uint256 amount, 
      FXRate calldata rate, 
      bytes calldata signature, 
      string calldata details) external override returns (bool) {
        // no modifier because it is expected to be called by anyone with a good fx rate
      return _settlement(from, to, amount, rate, signature, details);
    }
}