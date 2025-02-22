// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;


import {ISoCashBankExternal, ISoCashFXProvider} from "@so-cash/sc-so-cash/src/intf/so-cash-bank.sol";

type CodeType is bytes10;

struct BankIdentifier {
  bytes2 country;
  CodeType[] codes;
}


enum BankModel { UNDEFINED, SO_CASH, ERC20 }
// The structure where the bank want to be paid for a given currency
struct BankAccount {
  BankModel model; // 0: not defined, 1: so-cash account, 2: ERC20 account
  address bank; // the address of the bank or the ERC20 contract
  address account; // our account with this bank or the address to represent the ERC20 account (expected to be the address of CurrencyModule)
}

interface ISoCashGlobalReferential {
  event CountrySet(bytes2 indexed country, ISoCashCountryReferential indexed countryContract);
  // set by a global administrator - future governance model to be defined to prevent centralisation
  function setCountry(ISoCashCountryReferential countryContract) external;
  function getCountry(bytes2 country) external view returns (ISoCashCountryReferential);

  // function to resolve the routing, finding the sequence of banks to reach the provided bank from the provided bank
  function resolveRoute(bytes3 currency, BankIdentifier memory from, BankIdentifier memory target) external view returns (bool resolved, BankIdentifier[] memory route);

  // TODO: add a decodeIBAN function to resolve any IBAN based on the declared modules in the referential and use the Iban to Account of the bank module
}


interface ISoCashCountryReferential {
  function countryCode() external view returns (bytes2);

  // called only by the controller/owner of the country
  event BankControllerSet(CodeType indexed bankCode, address controller, bool indexed allowed);
  function setBankController(CodeType bankCode, address controller) external;
  function unsetBankController(CodeType bankCode, address controller) external;
  function isBankController(CodeType bankCode, address controller) external view returns (bool);
  
  // functions for the banks to setup its config. codes are one, two or possbly more codes to reach the bank (bank code, branch code ...)
  event BankModuleSet(CodeType indexed bankCode, CodeType[] codes, bytes3 indexed currency, ISoCashBankExternal indexed bankModule);
  event FXProviderSet(CodeType indexed bankCode, ISoCashFXProvider indexed fxProvider, bool indexed added);
  event CorrespondentBankChange(CodeType indexed bankCode, CodeType[] codes, bytes3 indexed currency, BankIdentifier correspondent, bool added);
  event SSIChange(CodeType indexed bankCode, CodeType[] codes, bytes3 indexed currency, BankAccount account);
  // called only by the controller of the bank to link its smart contract module to the bank/branch codes and currency
  function setBankModule(CodeType[] calldata codes, bytes3 currency, ISoCashBankExternal bankModule) external;
  // called only by the controller of the bank to set the bank via which it can be paid on a given currency
  function addCorrespondent(CodeType[] calldata codes, bytes3 currency, BankIdentifier calldata correspondent) external;
  function delCorrespondent(CodeType[] calldata codes, bytes3 currency, BankIdentifier calldata correspondent) external;
  // called only by the controller of the bank to declare a FX Provider
  function setFXProvider(CodeType bankCode, ISoCashFXProvider fxProvider) external;
  function unsetFXProvider(CodeType bankCode, ISoCashFXProvider fxProvider) external;

  
  // called only by the controller of the bank to declare a SSI for a given currency
  function setSSI(CodeType[] calldata codes, bytes3 currency, BankAccount calldata account) external;

  // functions to resolve the routing
  function getBankModule(CodeType[] memory codes, bytes3 currency) external view returns (ISoCashBankExternal);
  function getCorrespondentBanks(CodeType[] memory codes, bytes3 currency) external view returns (BankIdentifier[] memory correspondents);
  function isCorrespondent(CodeType[] memory codes, bytes3 currency, BankIdentifier memory correspondent) external view returns (bool);
  function getSSI(CodeType[] memory codes, bytes3 currency) external view returns (BankAccount memory account);
}