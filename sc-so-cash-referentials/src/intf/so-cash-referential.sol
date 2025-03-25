// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;



import {ISoCashBankExternal, ISoCashFXProvider} from "@so-cash/sc-so-cash/src/intf/so-cash-bank.sol";

type CodeType is bytes10;

struct BankIdentifier {
  bytes2 country;
  CodeType[] codes;
}


enum BankModel { UNDEFINED, SO_CASH, ERC20 }

///@title BankAccount 
///@notice The structure where the bank want to be paid for a given currency
struct BankAccount {
  BankModel model; // 0: not defined, 1: so-cash account, 2: ERC20 account
  address bank; // the address of the bank or the ERC20 contract
  address account; // our account with this bank or the address to represent the ERC20 account (expected to be the address of CurrencyModule)
}


/**
 * @title ISoCashCountryManagerInternal
 * @notice The interface for the internal functions of the CountryManager facet
 * @dev The interface collects the events that are emitted by the CountryManager facet
 */
interface ISoCashCountryManagerInternal {
  /** 
  * @notice Event emitted when a country is set in the referential
  * @dev When the param countryContract is ZeroAddress, it means the country is removed from the referential
  * @param country The ISO country code as a Ascii encoded bytes2. Typically you send `0x4652` for FR.
  * @param countryContract The country contract address for the given country code or ZeroAddress if the country is removed from the referential
  */
  event CountrySet(bytes2 indexed country, ISoCashCountryReferential indexed countryContract);
}

/** 
  * @title ISoCashCountryManager
  * @notice The interface for the CountryManager facet
  * @dev The interface is used to get and set the country contract in the referential
*/
interface ISoCashCountryManager {
  /**
  * @notice Set the country contract in the referential
  * @dev The function is expected to emit the CountrySet event.
  <br>The country code is not expected because it is retrieved from the country contract via the interface [ISoCashCountryStateManagement](./api-ISoCashCountryStateManagement)
  * @param countryContract The country contract to set in the referential. If Zero or not a compatible contract, the call fails when trying to get the country code.
   */
  function setCountry(ISoCashCountryReferential countryContract) external;
  
  /**
  * @notice Get the country contract from the referential
  * @dev The function returns the country contract address for the given country code or ZeroAddress if the country is not in the referential.
  * @param country The ISO country code as a Ascii encoded bytes2. Typically you send `0x4652` for FR.
  * @return contractAddress The country contract address for the given country code or ZeroAddress if the country is not in the referential.
   */
  function getCountry(bytes2 country) external view returns (ISoCashCountryReferential contractAddress);
}

/**
  * @title ISoCashPathFinder
  * @notice The interface for the PathFinder facet to resolve a payment path between banks
  * @dev The interface is used to resolve the routing, finding the sequence of banks to reach the provided bank from the provided bank
 */
interface ISoCashPathFinder {
  /**
  * @notice Resolve the routing between two banks
  * @dev The function returns the sequence of banks :
  <br>The function operates using the declared correspondents in the referential. 
  <br>It starts by the `target` bank, that holds the account of the beneficiary, and progress backward to the `from` bank, if found.
  <br>It returns the sequence of banks (identifier) ordered from the `from` bank to the `target` bank including both ends.
  @param currency The currency of the payment, expressed in ISO 4217 3 letters code. Typically you send `EUR` as `0x455552`.
  @param from The bank identifier of the bank where the payment starts.
  @param target The bank identifier of the bank where the beneficiary account is to be credited.
  @return resolved True if the routing is resolved, false otherwise, in which case the `route` is empty.
  @return route The sequence of banks (identifier) ordered from the `from` bank to the `target` bank including both ends.
   */
  function resolveRoute(bytes3 currency, BankIdentifier memory from, BankIdentifier memory target) external view returns (bool resolved, BankIdentifier[] memory route);
}


/**
  * @title ISoCashBankControllerInternal
  * @notice The interface for defining the events emitted by the BankController facet
  * @dev The interface is used to define the events emitted by the [ISoCashBankController](./api-ISoCashBankController) implementation
 */
interface ISoCashBankControllerInternal {
  /**
  * @notice Event emitted when a bank controller is set or removed for a bank
  * @dev The event is emitted by `setBankController` and `unsetBankController` functions
  * @param bankCode The bank code of the bank the controller wallet is given access to.
  * @param controller The address of the wallet that is given access to the bank.
  * @param allowed True if the controller is now allowed to access the bank, false if the controller is now disallowed to access the bank.
   */
  event BankControllerSet(CodeType indexed bankCode, address controller, bool indexed allowed);
}

/**
  * @title ISoCashBankController
  * @notice The interface for the BankController service that enables a country referential to allow banks to have the capacity to control their own declaration in the referential.
  * @dev The interface is used to set and unset the bank controller for a bank and check the current status of the controller.
  <br>Several controllers can be set for a particular bank code.
 */
interface ISoCashBankController {
  /**
  * @notice Set the bank controller for a bank code
  * @dev The function is expected to emit the BankControllerSet event.
  <br>Only an allowed wallet for the country referential should be allowed to call this function. 
  <br>Note that the wallet address can be the address of another smart contract that the bank is using to automate its declaration in the referential.
  * @param bankCode The bank code of the bank the controller wallet is given access to.
  * @param controller The address of the wallet that is given access to the bank.
   */
  function setBankController(CodeType bankCode, address controller) external;

  /**
  * @notice Unset the bank controller for a bank code
  * @dev The function is expected to emit the BankControllerSet event.
  <br>Only an allowed wallet for the country referential should be allowed to call this function.
  * @param bankCode The bank code of the bank the controller wallet is removed from.
  * @param controller The address of the wallet that is removed from the bank.
   */
  function unsetBankController(CodeType bankCode, address controller) external;

  /**
  * @notice Check if a wallet is a controller for a bank code
  * @dev The function returns true if the wallet is a controller for the bank code, false otherwise.
  * @param bankCode The bank code of the bank to check the controller for.
  * @param controller The address of the wallet to check if it is a controller for the bank.
  * @return True if the wallet is a controller for the bank code, false otherwise.
   */
  function isBankController(CodeType bankCode, address controller) external view returns (bool);
}

/**
  * @title ISoCashCountryStateManagement
  * @notice The interface for banks to records elements in a country referential
  * @dev The interface is used to set the bank module, the correspondent bank, the SSI and the FX provider by a controller of a bank.
  <br>Functions are typically controlling that the caller is the controller for the `bankCode`
 */
interface ISoCashCountryStateManagement {
  /**
    * @notice get the country code of this country referential
    * @dev The function returns the country code of the country referential implementation.
    * @return The country code of the country referential in bytes like `0x4652` for `FR`.
   */
  function countryCode() external view returns (bytes2);

  // functions for the banks to setup its config. codes are one, two or possbly more codes to reach the bank (bank code, branch code ...)

  /**
  * @notice Event emitted when a bank module is set for a bank
  * @dev The event is emitted by `setBankModule` function
  * @param bankCode The bank code of the bank the module is set for.
  * @param codes The additional codes that defines the bank module. Typically the branch code. Any number of codes can be set.
  * @param currency The currency managed by the bank module.
  * @param bankModule The address of the bank module that is set for the bank. Typically a [ISoCashBankExternal](./api-ISoCashBankExternal) contract.
   */
  event BankModuleSet(CodeType indexed bankCode, CodeType[] codes, bytes3 indexed currency, ISoCashBankExternal indexed bankModule);

  /**
  * @notice Event emitted when a FX provider is set for a bank
  * @dev The event is emitted by `setFXProvider` and `unsetFXProvider` functions
  * @param bankCode The bank code of the bank the FX provider is set for. Note that a FX Provided does not have to be a full bank as it does not need to keep accounts for clients.
  * @param fxProvider The address of the FX provider that is set for the bank. Typically a [ISoCashFXProvider](./api-ISoCashFXProvider) contract.
  * @param added True if the FX provider is added, false if the FX provider is removed.
  */
  event FXProviderSet(CodeType indexed bankCode, ISoCashFXProvider indexed fxProvider, bool indexed added);

  /**
  * @notice Event emitted when a correspondent bank is set for a bank
  * @dev The event is emitted by `addCorrespondent` and `delCorrespondent` functions
  * @param bankCode The bank code of the bank the correspondent bank is set for.
  * @param codes The additional codes that defines the bank module that defines this correspondent
  * @param currency The currency managed by the correspondent bank.
  * @param correspondent The bank identifier of the correspondent bank that is set for the bank.
  * @param added True if the correspondent bank is added, false if the correspondent bank is removed.
   */
  event CorrespondentBankChange(CodeType indexed bankCode, CodeType[] codes, bytes3 indexed currency, BankIdentifier correspondent, bool added);

  /**
  * @notice Event emitted when a SSI is set for a bank
  * @dev The event is emitted by `setSSI` function
  * @param bankCode The bank code of the bank the SSI is set for.
  * @param codes The additional codes that defines the bank module that defines this SSI
  * @param currency The currency of the SSI.
  * @param account The bank account that is set for the bank. Can be a so|cash account or an ERC20 account.
  */
  event SSIChange(CodeType indexed bankCode, CodeType[] codes, bytes3 indexed currency, BankAccount account);


  /**
  * @notice Set the bank module contract for a bank defined by its codes
  * @dev The function is expected to emit the BankModuleSet event.
  <br>Only the controller of the bank should be allowed to call this function.
  * @param codes The codes that defines the bank module. Typically the bank code, branch code. Any number of codes can be set.
  * @param currency The currency managed by the bank module.
  * @param bankModule The address of the bank module that is set for the bank. Typically a [ISoCashBankExternal](./api-ISoCashBankExternal) contract.
   */
  function setBankModule(CodeType[] calldata codes, bytes3 currency, ISoCashBankExternal bankModule) external;

  /**
  * @notice Add a correspondent bank for a bank defined by its codes. 
  <br>A Correspondent is a bank that can sent payment instruction to the bank and therefore call the `interbankTransfer()` function in the [ISoCashInterBank](./api-ISoCashInterBank) interface.
  * @dev The function is expected to emit the CorrespondentBankChange event.
  <br>Only the controller of the bank should be allowed to call this function.
  * @param codes The codes that defines the bank module that defines this correspondent
  * @param currency The currency managed by the correspondent bank.
  * @param correspondent The bank identifier of the correspondent bank that is set for the bank.
   */
  function addCorrespondent(CodeType[] calldata codes, bytes3 currency, BankIdentifier calldata correspondent) external;

  /**
  * @notice Remove a correspondent bank for a bank defined by its codes.
  * @dev The function is expected to emit the CorrespondentBankChange event.
  <br>Only the controller of the bank should be allowed to call this function.
  * @param codes The codes that defines the bank module that defines this correspondent
  * @param currency The currency managed by the correspondent bank.
  * @param correspondent The bank identifier of the correspondent bank that is removed for the bank.
   */
  function delCorrespondent(CodeType[] calldata codes, bytes3 currency, BankIdentifier calldata correspondent) external;
  
  /**
  * @notice Set the FX provider for a bank
  * @dev The function is expected to emit the FXProviderSet event.
  <br>The Fx provider does not need to be unique per bank code, there is no state recording of the FX Provided in the chain, only the event enables developpers to find the FX provider for a bank.
  <br>Only the controller of the bank should be allowed to call this function.
  * @param bankCode The bank code of the bank the FX provider is set for.
  * @param fxProvider The address of the FX provider that is set for the bank. Typically a [ISoCashFXProvider](./api-ISoCashFXProvider) contract.
   */
  function setFXProvider(CodeType bankCode, ISoCashFXProvider fxProvider) external;

  /**
  * @notice Remove the FX provider for a bank
  * @dev The function is expected to emit the FXProviderSet event.
  <br>Only the controller of the bank should be allowed to call this function.
  * @param bankCode The bank code of the bank the FX provider is removed for.
  * @param fxProvider The address of the FX provider that is removed for the bank.
   */
  function unsetFXProvider(CodeType bankCode, ISoCashFXProvider fxProvider) external;

  
  /**
  * @notice Set the SSI for a bank
  * @dev The function is expected to emit the SSIChange event.
  <br>Only the controller of the bank should be allowed to call this function.
  * @param codes The codes that defines the bank module that defines this SSI
  * @param currency The currency of the SSI.
  * @param account The bank account that is set for the bank. Can be a so|cash account or an ERC20 account.
   */
  function setSSI(CodeType[] calldata codes, bytes3 currency, BankAccount calldata account) external;

  /**
  * @notice Get the bank module for a bank defined by its codes and currency
  * @dev The function returns the bank module for the bank defined by its codes and currency or zero if not found.
  * @param codes The codes that defines the bank module. Typically the bank code, branch code. Any number of codes can be set.
  * @param currency The currency managed by the bank module.
  * @return The bank module for the bank defined by its codes and currency or zero if not found.
   */
  function getBankModule(CodeType[] memory codes, bytes3 currency) external view returns (ISoCashBankExternal);

  /**
    * @notice Get the correspondent banks for a bank defined by its codes and currency
    <br>Returns the list of banks that are allowed to send payment instructions to the bank.
    * @dev The function returns the list of correspondent banks defined by their country, codes. The result can be empty.
    * @param codes The codes that defines the bank module reachable by these correspondents
    * @param currency The currency managed by the correspondent banks.
    * @return correspondents The list of correspondent banks for the bank defined by its codes and currency.
   */
  function getCorrespondentBanks(CodeType[] memory codes, bytes3 currency) external view returns (BankIdentifier[] memory correspondents);

  /**
  * @notice Check if a bank is a correspondent for the provided bank
  * @dev The function returns true if the bank is a correspondent for the provided bank, false otherwise.
  * @param codes The codes that defines the bank module that is expected to have the correspondent
  * @param currency The currency managed by the correspondent bank.
  * @param correspondent The bank identifier of the correspondent bank that is checked for the bank.
  * @return True if the bank is a correspondent for the provided bank, false otherwise.
   */
  function isCorrespondent(CodeType[] memory codes, bytes3 currency, BankIdentifier memory correspondent) external view returns (bool);

  /**
  * @notice Get the Default Settlement Instructions (SSI) for a bank and currency
  <br>For the moment a single SSI can be defined by bank and currency.
  * @dev The function returns the SSI for the bank defined by its codes and currency or zeros if not found.
  * @param codes The codes that defines the bank module that defines this SSI
  * @param currency The currency of the SSI.
  * @return account The SSI for the bank defined by its codes and currency or zeros if not found.
   */
  function getSSI(CodeType[] memory codes, bytes3 currency) external view returns (BankAccount memory account);
}


/**
  * @title ISoCashGlobalReferential
  * @notice The interface for the GlobalReferential 
  * @dev The interface is used to get the country manager, the country manager internal and the path finder
  <br>Inherits from the [ISoCashCountryManager](./api-ISoCashCountryManager), [ISoCashCountryManagerInternal](./api-ISoCashCountryManagerInternal) and [ISoCashPathFinder](./api-ISoCashPathFinder) interfaces
 */
interface ISoCashGlobalReferential is ISoCashCountryManager, ISoCashCountryManagerInternal, ISoCashPathFinder {
}


/**
  * @title ISoCashCountryReferential
  * @notice The interface for the CountryReferential 
  * @dev The interface is used to get the country code, the bank module, the correspondent banks, the FX provider and the SSI
  <br>Inherits from the [ISoCashBankController](./api-ISoCashBankController), [ISoCashBankControllerInternal](./api-ISoCashBankControllerInternal) and [ISoCashCountryStateManagement](./api-ISoCashCountryStateManagement) interfaces
 */
interface ISoCashCountryReferential is ISoCashBankController, ISoCashBankControllerInternal, ISoCashCountryStateManagement {

}