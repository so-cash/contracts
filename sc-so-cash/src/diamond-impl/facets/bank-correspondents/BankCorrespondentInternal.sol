// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import { IERC20 } from "@fever-tokens/diamond/src/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@fever-tokens/diamond/src/token/ERC20/extensions/IERC20Metadata.sol";

import {
  ISoCashGlobalReferential, 
  ISoCashCountryReferential,
  BankIdentifier,
  CodeType
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {
  ISoCashBank,
  ISoCashAccount,
  RecipentInfo,
  NostroAccount,
  BankModel,
  OperationDirection,
  TransferId,
  BankAccount,
  AccountNumber,
  CCY, IBAN, BIC,
  ZERO_BANK,
  ZERO_ACCOUNT
  } from "../../../intf/so-cash-types.sol";
import {
  ISoCashOwnedAccount
} from "../../../intf/so-cash-account.sol";
import {
  ISoCashInterBank,
  ISoCashBankExternal,
  ISoCashBankNostroManagementInternal
} from "../../../intf/so-cash-bank.sol";
import {BankIdentityInternal} from "../bank-identity/BankIdentityInternal.sol";
import {SharedFunctions} from "../../libs/SharedFunctions.sol";
import {LocalIBANCalculator} from "../iban/IBANService.sol";

contract BankCorrespondentInternal is BankIdentityInternal {
  modifier onlyCorrespondentBank() {
    require(_isCorrespondentRegistered(ISoCashBank(msg.sender)), "SoC: Only a correspondent bank can call this function");
    _;
  }

  function _isCorrespondentRegistered(ISoCashBank bank) internal view returns (bool) {
    if (!SharedFunctions.notNullBank(bank)) return false;
    ISoCashCountryReferential country = _getCountryReferential();
    // get the identifier of the calling bank
    BankIdentifier memory caller = SharedFunctions._ibe(bank).bankIdentifier();
    bool isCB = country.isCorrespondent(_bankIdentifier().codes, CCY.unwrap(_ccy()), caller);
    return isCB;
  }

  function _decodeIBANIntoIdentifier(string memory iban) internal pure returns (BankIdentifier memory bankId, string memory account, bytes3 currency) {
    (bool valid, string memory country, string memory bankCode5, string memory branchCode5, string memory accountNumber11, ) 
      = LocalIBANCalculator.extractFrenchIBAN(iban);
    require(valid, "SoC: Invalid IBAN format");
    bankId.codes = new CodeType[](2);
    account = accountNumber11;
    // Extract the currency from the account number as currency the convention is to have the currency at the beginning of the account number
    currency = SharedFunctions.stringToBytes3(accountNumber11);
    // create the bank identifier
    bankId.country = SharedFunctions.stringToBytes2(country);
    bankId.codes[0] = CodeType.wrap(SharedFunctions.stringToBytes10(bankCode5));
    bankId.codes[1] = CodeType.wrap(SharedFunctions.stringToBytes10(branchCode5));
  }

  function _getCountryRef(bytes2 country) internal view returns (ISoCashCountryReferential) {
    ISoCashGlobalReferential ref = _referential();
    ISoCashCountryReferential refCountry = ref.getCountry(country);
    require(SharedFunctions.notNullCountryRef(refCountry), "SoC: Country referential not found");
    return refCountry;
  }

  function _getBankModule(BankIdentifier memory bankId, CCY currency) internal view returns (ISoCashBank) {
    ISoCashCountryReferential refCountry = _getCountryRef(bankId.country);
    ISoCashBank bank = ISoCashBank(address(refCountry.getBankModule(bankId.codes, CCY.unwrap(currency))));
    require(SharedFunctions.notNullBank(bank), "SoC: Bank module not found");
    return bank;
  }

  function _decodeIBANToSoCashContracts(string memory iban) internal view returns (ISoCashBank bank, ISoCashAccount account, BankIdentifier memory) {
    (BankIdentifier memory bankId, string memory accountNumber, bytes3 currency) = _decodeIBANIntoIdentifier(iban);
    // force the conversions because the import of libraries differs making it a different type even if it is the same source
    bank = _getBankModule(bankId, CCY.wrap(currency));
    account = ISoCashBankExternal(address(bank)).addressOfFullAccount(accountNumber);
    return (bank, account, bankId);
  }

  // Function to cast bytes10 to bytes5 and force the reduction of size to 5 bytes
  function toBytes5(CodeType input) internal pure returns (bytes5) {
    return bytes5(CodeType.unwrap(input));
  }
  function _encodeIbanOfAccount(AccountNumber an) internal view returns (string memory) {
    BankIdentifier memory _bankId = _bankIdentifier();
    string memory country2 = string(abi.encodePacked(_bankId.country));
    string memory bankCode5 = string(abi.encodePacked(toBytes5(_bankId.codes[0])));
    string memory branchCode5 = string(abi.encodePacked(toBytes5(_bankId.codes[1])));
    string memory accountNumber11 = LocalIBANCalculator.uintToString(AccountNumber.unwrap(an));
    accountNumber11 = LocalIBANCalculator.padWithZeros(accountNumber11, 8);
    accountNumber11 = string(abi.encodePacked(_ccy(), accountNumber11));
    
    string memory ibanStr = LocalIBANCalculator.calculateFrenchIBAN(country2, bankCode5, branchCode5, accountNumber11);
    return ibanStr;
  }


  function _getSoCashAccountOfRecipient(
    RecipentInfo memory recipient
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
        // Extract the bank identifier from the IBAN and the account string
        (bank, account, ) = _decodeIBANToSoCashContracts(iban);
      }
      // In all other cases, the bank and account are zeroed
    }
  }

  /**
  * Returns the BankIdentifier (codes and country) of the target bank and the onchain instance of the bank and the account if it is local
   */
  function _getTargetBankIdentifier(
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
        (onchain, account, targetBank) = _decodeIBANToSoCashContracts(iban);
        require(SharedFunctions.notNullAccount(account), "SoC PE: Target account not found in the bank");
        return (targetBank, onchain, account);
      } else {
        // The IBAN was not specified, we should have a BIC
        if (BIC.unwrap(recipient.bic) != 0) {
          // only a BIC has been specified, this cannot be handled properly for now 
          // TODO: We would need to add the BIC in the referential 
          // check that it is our BIC
          if (BIC.unwrap(_bic()) == BIC.unwrap(recipient.bic)) {
            // return as if we need to transfer to zero (burn the balance)
            return (_bankIdentifier(), ISoCashBank(address(this)), ZERO_ACCOUNT);
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
    Provides the BankIdentifier and if available its onchain address 
   */
  function _resolveCorrespondentBank(
    BankIdentifier memory targetBank, 
    ISoCashBank targetOnchain) internal view returns (BankIdentifier memory id, ISoCashBank onchain, BankAccount memory ssi) {
    ISoCashBank self = ISoCashBank(address(this));
    BankIdentifier memory selfId = _bankIdentifier();
    CCY ccy = _ccy();
    ISoCashCountryReferential country = _getCountryRef(selfId.country);
    
    // If we target ourself (should not happen but added for consistency)
    if (targetOnchain == self) return (targetBank, self, BankAccount( BankModel.UNDEFINED, address(0), address(0)) ); 
    
    // First look locally if the target bank is a correspondent
    if (country.isCorrespondent(selfId.codes, CCY.unwrap(ccy), targetBank)) { // target bank is a correspondent so this is the next bank
      country = _getCountryRef(targetBank.country);
      BankAccount memory account = country.getSSI(targetBank.codes, CCY.unwrap(ccy));
      return (targetBank, targetOnchain, account);
    } else {
      // The target bank is not a correspondent, we need to find a route to it using the referential
      
      (bool resolved, BankIdentifier[] memory route) = _referential().resolveRoute(CCY.unwrap(ccy), selfId, targetBank);
      if (resolved && route.length>=2) {
        // the first of the route is us
        // the second is a correspondent bank, no need to control because the referential is the golden source
        country = _getCountryRef(route[1].country);
        ISoCashBank bank = _getBankModule(route[1], ccy);
        BankAccount memory account = country.getSSI(route[1].codes, CCY.unwrap(ccy));
        return (route[1], bank, account);
      }
    }
    require(false, "SoC PE: Could not find a route to the target bank");
  }
}