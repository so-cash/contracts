// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {ERC20MetadataStorage} from "@fever-tokens/diamond/src/token/ERC20/extensions/ERC20MetadataStorage.sol";

import {
  ISoCashGlobalReferential, 
  ISoCashCountryReferential,
  BankIdentifier
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {BIC, CCY} from "../../../intf/so-cash-types.sol";
import {BankIdentityStorage} from "./BankIdentityStorage.sol";

contract BankIdentityInternal {

  function _referential() internal view returns (ISoCashGlobalReferential) {
    BankIdentityStorage.Layout storage l = BankIdentityStorage.layout();
    // this is a protection against bad initialization
    require(address(l.referential) != address(0), "SoC: Referential not set");
    return l.referential;
  }

  function _bic() internal view returns (BIC) {
    return BankIdentityStorage.layout().bic;
  }

  function _bankIdentifier() internal view returns (BankIdentifier memory) {
    return BankIdentityStorage.layout().bankIdentifier;
  }

  function _country() internal view returns (bytes2 ) {
    return BankIdentityStorage.layout().bankIdentifier.country;
  }

  function _version() internal view returns (string memory) {
    return BankIdentityStorage.layout().version;
  }

  function _ccy() internal view returns (CCY) {
    string memory ccy = ERC20MetadataStorage.layout().symbol;
    return CCY.wrap(bytes3(abi.encodePacked(ccy)));
  }

  function _getCountryReferential() internal view returns (ISoCashCountryReferential) {
    ISoCashGlobalReferential _routingRef = _referential();
    ISoCashCountryReferential country = _routingRef.getCountry(_country());
    require(address(country)!=address(0), string(abi.encodePacked("SoC: Country ref ", _country(), " not found")));
    return country;
  } 
}  