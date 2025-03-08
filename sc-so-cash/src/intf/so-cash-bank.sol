// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IERC20Internal} from "@fever-tokens/diamond/src/token/ERC20/IERC20Internal.sol";
import "./so-cash-types.sol";
import {BankIdentifier, BankAccount} from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";

import {IWhitelistedSenders} from "./whitelisted-senders.sol";

interface IERC20CompatibilityMetadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IERC20CompatibilityBaseInternal is IERC20Internal {
    // compatibility with ERC20 event
    // declares
    // event Transfer(address indexed from, address indexed to, uint256 value);
}

interface IERC20CompatibilityBase is IERC20CompatibilityBaseInternal {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
}
interface IERC20Compatibility is IERC20CompatibilityBaseInternal, IERC20CompatibilityMetadata{
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface ISoCashBankIdentity {
    function version () external view returns (string memory);
    function bic() external view returns (string memory);
    function codes() external view returns (CodeType bankCode, CodeType branchCode);
    function bankIdentifier() external view returns (BankIdentifier memory id);
}
interface ISoCashBankBalanceManagementInternal {
    event AccountRegistration(ISoCashAccount indexed account, bool registered);
    event AccountActivation(ISoCashAccount indexed account, bool active);

    event TransferEx(ISoCashAccount indexed from, ISoCashAccount indexed to, uint256 value, TransferId indexed id);
}

interface ISoCashBankBalanceManagement is ISoCashBankBalanceManagementInternal {
    function lockedBalanceOf(ISoCashAccount account) external view returns (uint256);
    function unlockedBalanceOf(ISoCashAccount account) external view returns (uint256);
    function fullBalanceOf(ISoCashAccount account) external view returns (int256);
    function accountNumberOf(ISoCashAccount account) external view returns (AccountNumber);
    function addressOf(AccountNumber accountNumber) external view returns (ISoCashAccount);
    function addressOfFullAccount(string memory account) external view returns (ISoCashAccount);

}

interface ISoCashBankExternalTransfer {
    function transfer(RecipentInfo calldata to, uint256 amount, string calldata details) external returns (bool);
}

interface ISoCashBankExternalWOTransfer is IERC20Compatibility, ISoCashBankIdentity, ISoCashBankBalanceManagement {

    function transferInfo(TransferId id) external view returns (TransferInfo memory);

    function lockFunds(uint256 amount) external returns (bool);
    function unlockFunds(uint256 amount) external returns (bool);

    function ibanOf(ISoCashAccount account) external view returns (string memory);
    function decodeIBAN(string memory iban) external view returns (ISoCashBank bank, ISoCashAccount account);
}
interface ISoCashBankExternal is ISoCashBankExternalWOTransfer, ISoCashBankExternalTransfer {

    function transferInfo(TransferId id) external view returns (TransferInfo memory);

    function lockFunds(uint256 amount) external returns (bool);
    function unlockFunds(uint256 amount) external returns (bool);

    function ibanOf(ISoCashAccount account) external view returns (string memory);
    function decodeIBAN(string memory iban) external view returns (ISoCashBank bank, ISoCashAccount account);
}

interface ISoCashBankPaymentInternal {
    event Adviced(ISoCashBank indexed target, ISoCashAccount indexed account, uint256 amount, OperationDirection direction, TransferId indexed id);

}

interface ISoCashInterBank is ISoCashBankPaymentInternal{

    function interbankTransfer(BankAccount calldata ssi, RecipentInfo calldata to, uint256 amount, TransferId id) external returns (bool);
    function interbankNetting(uint256 amount, TransferId id) external returns (bool);
    function advice(uint256 amount, OperationDirection direction, TransferId id) external returns (bool);
}

interface ISoCashBankTransferManagementInternal {
    event TransfertStateChanged(TransferId indexed id, TransferStatus status);
}

interface ISoCashBankNostroManagementInternal {
    event NostroAccountRegistration(BankModel model, address indexed bank, address indexed account, bool registered);

}

interface ISoCashBackOfficePayments {
    function transferFrom(ISoCashAccount from, RecipentInfo calldata to, uint256 amount, string calldata details) external returns (bool);

    // function creditNostro(ISoCashAccount nostro, uint256 amount, string calldata details) external returns (bool);
    function requestNetting(ISoCashBank correspondent, ISoCashAccount loro, uint256 amount) external returns (bool);
    function synchroNostro(address bank, address account) external returns (bool);

    function decidePendingTransfer(TransferId id, TransferStatus status, string memory reason) external returns (bool);
}

interface ISoCashBankBackOfficeServices {
    event BankCreation(ISoCashBank indexed bank, string bic, string currency);
    event BankRegistration(ISoCashBank indexed bank, bool registered);

    // function registerCorrespondent(ISoCashBank correspondent) external returns (bool);
    // function unregisterCorrespondent(ISoCashBank correspondent) external returns (bool);
    function isCorrespondentRegistered(ISoCashBank correspondent) external view returns (bool);
    function correspondent(ISoCashBank correspondent) external view returns (BankIdentifier memory cb);

    function registerAccount(ISoCashAccount account) external returns (bool);
    function unregisterAccount(ISoCashAccount account) external returns (bool);
    function isAccountRegistered(ISoCashAccount account) external view returns (bool);
    function toggleAccountActive(ISoCashAccount account) external returns (bool);
    function isAccountActive(ISoCashAccount account) external view returns (bool);

    function registerNostroAccount(BankAccount calldata nostro) external returns (bool);
    function unregisterNostroAccount(address bank, address account) external returns (bool);
    function nostroAccountModel(address bank, address account) external view returns (BankModel);
    function getNostroBalance(address bank, address account) external view returns (int256 actual, int256 last);

    function credit(ISoCashAccount account, uint256 amount, string calldata details) external returns (bool);
    function debit(ISoCashAccount account, uint256 amount, string calldata details) external returns (bool);
    function lockFunds(ISoCashAccount account, uint256 amount) external returns (bool);
    function unlockFunds(ISoCashAccount account, uint256 amount) external returns (bool);
}

interface ISoCashBankBackOffice is ISoCashBankBackOfficeServices, ISoCashBackOfficePayments, ISoCashBankTransferManagementInternal, ISoCashBankNostroManagementInternal, ISoCashBankBalanceManagementInternal{
}

interface ISoCashBankExplainPlan {
    // event that is not a public api purpose but is usefull for debugging the execution plan
    event ExplainPlan(ExecutionPlan plan);
}

interface ISoCashBankPaymentSimulation {
    function simulateTransfer(ISoCashAccount fromAccount, RecipentInfo memory to, uint256 amount) external view returns (ExecutionPlan memory);
    function simulateInterbankTransfer(ISoCashBank fromBank, RecipentInfo memory to, uint256 amount) external view returns (ExecutionPlan memory plan);
}
interface ISoCashBankFull is IWhitelistedSenders, ISoCashBankExternal, ISoCashInterBank, ISoCashBankBackOffice, ISoCashBankPaymentSimulation, ISoCashBankExplainPlan {
}



interface ISoCashFXProviderInternal {
    event CurrencyAccountSet(CCY indexed ccy, ISoCashAccount account);
    event FXSettlement(ISoCashAccount indexed from, ISoCashAccount indexed to, uint256 amount, uint256 rate);
}
interface ISoCashFXProvider is ISoCashFXProviderInternal{
    function setCurrencyAccount(CCY ccy, ISoCashAccount account) external;

    function setFXRateSource(CCY base, CCY quote, string calldata source) external;
    function getFXRateSource(CCY base, CCY quote) external view returns (string memory);

    function setRateSigner(address signer) external;
    function getRateSigner() external view returns (address);

    function hashOfFXRate(FXRate memory rate) external view returns (bytes32);
    function verifyFXRate(FXRate memory rate, bytes memory signature) external view returns (bool);
    function settlement(RecipentInfo calldata from, RecipentInfo calldata to, uint256 amount, FXRate calldata rate, bytes calldata signature, string calldata details) external returns (bool);
}

interface ISoCashFXProviderFull is ISoCashFXProvider, IWhitelistedSenders, ISoCashBankIdentity {}