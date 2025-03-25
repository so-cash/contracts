// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {
  ISoCashBankExternal,
  ISoCashFXProvider} from "@so-cash/sc-so-cash/src/intf/so-cash-bank.sol";

import {
  CodeType,
  BankIdentifier,
  BankAccount,
  ISoCashCountryStateManagement} from "../intf/so-cash-referential.sol";
import {CountryStateStorage} from "./CountryStateStorage.sol";
import {BankControllerInternal} from "./BankControllerInternal.sol";

contract CountryStateManagementInternal {
  function _countryCode() internal view returns (bytes2) {
    return CountryStateStorage.layout().countryCode;
  }

  function copyCodes(CodeType[] memory codes, uint from, uint to) internal pure returns (CodeType[] memory) {
    if (to == 0) to = codes.length;
    CodeType[] memory _codes = new CodeType[](to-from);
    uint j = 0;
    for(uint i=from; i<to; i++) {
      // emit debug(string(abi.encodePacked("copy ", bytes1(uint8(48+i)))), codes[i]);
      _codes[j++] = codes[i];
    }
    return _codes;
  }

  // create a bytes32 with the hash of the country and all codes in sequence
  function _index(CodeType[] memory codes) internal view returns (bytes32) {
    require(codes.length > 0, "At least one code is required");
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    bytes32 index = keccak256(abi.encodePacked(l.countryCode));
    for (uint i = 0; i < codes.length; i++) {
      index = keccak256(abi.encodePacked(index, codes[i]));
    }
    return index;
  }


  function _getBankModule(CodeType[] memory codes, bytes3 currency) internal view returns (ISoCashBankExternal) {
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    return l.bankModules[_index(codes)][currency];
  }
}

contract CountryStateManagement is ISoCashCountryStateManagement, CountryStateManagementInternal, BankControllerInternal {

  function countryCode() external view returns (bytes2) {
    return _countryCode();
  }

  /** 
    * @dev Set the bank module for a bank identified by the codes and currency
    * @param codes The bank codes. ATTENTION: The codes must be sent as an array of Buffer of exactly 10 bytes even of the code is shorter
    * @param currency The currency code sent as a Buffer of 3 bytes
    * @param bankModule The bank module to set
   */
  function setBankModule(CodeType[] calldata codes, bytes3 currency, ISoCashBankExternal bankModule) onlyBankController(codes) public override {
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    l.bankModules[_index(codes)][currency] = bankModule;
    emit BankModuleSet(codes[0], codes[1:], currency, bankModule);
  }

  /**
    * @dev Add a correspondent bank for a bank identified by the codes and currency
    * @param codes The bank codes. ATTENTION: The codes must be sent as an array of Buffer of exactly 10 bytes even of the code is shorter
    * @param currency The currency code sent as a Buffer of 3 bytes
    * @param correspondent The correspondent bank to set. In this structures the codes must be sent as an array of Buffer of exactly 10 bytes even of the code is shorter
   */
  function addCorrespondent(CodeType[] calldata codes, bytes3 currency, BankIdentifier calldata correspondent) onlyBankController(codes) public override {
    bytes32 corrId = _index(correspondent.codes);
    // save the correspondent bank info in the bankIds if it is not already saved
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    if( l.bankIds[corrId].country == 0 ) l.bankIds[corrId] = correspondent;
    l.correspondentBanks[_index(codes)][currency].push(corrId);
    emit CorrespondentBankChange(codes[0], codes[1:], currency, correspondent, true);
  }

  function delCorrespondent(CodeType[] calldata codes, bytes3 currency, BankIdentifier calldata correspondent) onlyBankController(codes) public override {
    bytes32 corrId = _index(correspondent.codes);
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    bytes32[] storage records = l.correspondentBanks[_index(codes)][currency];
    for (uint i = 0; i < records.length; i++) {
      if (records[i] == corrId) {
        if (i < records.length - 1) { // if not the last element
          records[i] = records[records.length - 1]; // move the last element to the position of the element to delete
        }
        records.pop(); // remove the last element
        emit CorrespondentBankChange(codes[0], codes[1:], currency, correspondent, false);
        return;
      }
    }
  }


  function setFXProvider(CodeType bankCode, ISoCashFXProvider fxProvider) onlyBankController1(bankCode) public override {
    // no storage, just raise the event
    emit FXProviderSet(bankCode, fxProvider, true);
  }
  function unsetFXProvider(CodeType bankCode, ISoCashFXProvider fxProvider) onlyBankController1(bankCode) public override {
    // no storage, just raise the event
    emit FXProviderSet(bankCode, fxProvider, false);
  }


  function setSSI(CodeType[] calldata codes, bytes3 currency, BankAccount calldata account) onlyBankController(codes) public override {
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    l.SSIs[_index(codes)][currency] = account;
    emit SSIChange(codes[0], codes[1:], currency, account);
  }

  function getBankModule(CodeType[] memory codes, bytes3 currency) external view override returns (ISoCashBankExternal) {
    return _getBankModule(codes, currency);
  }

  function getCorrespondentBanks(CodeType[] memory codes, bytes3 currency) external view override returns (BankIdentifier[] memory correspondents) {
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    bytes32[] storage records = l.correspondentBanks[_index(codes)][currency];
    correspondents = new BankIdentifier[](records.length);
    for (uint i = 0; i < records.length; i++) {
      correspondents[i] = l.bankIds[records[i]];
    }
    return correspondents;
  }

  function isCorrespondent(CodeType[] memory codes, bytes3 currency, BankIdentifier memory correspondent) external view override returns (bool) {
    bytes32 corrId = _index(correspondent.codes);
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    bytes32[] storage records = l.correspondentBanks[_index(codes)][currency];
    for (uint i = 0; i < records.length; i++) {
      if (records[i] == corrId) return true;
    }
    return false;
  }

  function getSSI(CodeType[] memory codes, bytes3 currency) external view override returns (BankAccount memory account) {
    CountryStateStorage.Layout storage l = CountryStateStorage.layout();
    return l.SSIs[_index(codes)][currency];
  }

  // function addition() external pure returns (uint) {
  //   return 1;
  // }
}