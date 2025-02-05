// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./so-cash-types.sol";
import {BankIdentifier, BankAccount} from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";



interface IERC20Compatibility {
    // compatibility with ERC20 event
    event Transfer(address indexed from, address indexed to, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface ISoCashBankExternal is IERC20Compatibility {
    event TransferEx(ISoCashAccount indexed from, ISoCashAccount indexed to, uint256 value, TransferId indexed id);

    function transferInfo(TransferId id) external view returns (TransferInfo memory);

    function transfer(RecipentInfo calldata to, uint256 amount, string calldata details) external returns (bool);
    function lockFunds(uint256 amount) external returns (bool);
    function unlockFunds(uint256 amount) external returns (bool);
    function lockedBalanceOf(ISoCashAccount account) external view returns (uint256);
    function unlockedBalanceOf(ISoCashAccount account) external view returns (uint256);
    function fullBalanceOf(ISoCashAccount account) external view returns (int256);

    function bic() external view returns (string memory);
    function codes() external view returns (CodeType bankCode, CodeType branchCode);
    function bankIdentifier() external view returns (BankIdentifier memory id);
    function ibanOf(ISoCashAccount account) external view returns (string memory);
    function accountNumberOf(ISoCashAccount account) external view returns (AccountNumber);
    function addressOf(AccountNumber accountNumber) external view returns (ISoCashAccount);
    function addressOfFullAccount(string memory account) external view returns (ISoCashAccount);
    function decodeIBAN(string memory iban) external view returns (ISoCashBank bank, ISoCashAccount account);
}

interface ISoCashInterBank {
    event Adviced(ISoCashBank indexed target, ISoCashAccount indexed account, uint256 amount, OperationDirection direction, TransferId indexed id);

    function interbankTransfer(BankAccount calldata ssi, RecipentInfo calldata to, uint256 amount, TransferId id) external returns (bool);
    function interbankNetting(uint256 amount, TransferId id) external returns (bool);
    function advice(uint256 amount, OperationDirection direction, TransferId id) external returns (bool);
}

interface ISoCashBankBackOffice {
    event BankCreation(ISoCashBank indexed bank, string bic, string currency);
    event BankRegistration(ISoCashBank indexed bank, bool registered);
    event AccountRegistration(ISoCashAccount indexed account, bool registered);
    event AccountActivation(ISoCashAccount indexed account, bool active);
    event TransfertStateChanged(TransferId indexed id, TransferStatus status);
    event NostroAccountRegistration(BankModel model, address indexed bank, address indexed account, bool registered);

    // function registerCorrespondent(ISoCashBank correspondent) external returns (bool);
    // function unregisterCorrespondent(ISoCashBank correspondent) external returns (bool);
    function isCorrespondentRegistered(ISoCashBank correspondent) external view returns (bool);
    // TODO: remove as not used
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
    function transferFrom(ISoCashAccount from, RecipentInfo calldata to, uint256 amount, string calldata details) external returns (bool);

    // function creditNostro(ISoCashAccount nostro, uint256 amount, string calldata details) external returns (bool);
    function requestNetting(ISoCashBank correspondent, ISoCashAccount loro, uint256 amount) external returns (bool);
    function synchroNostro(address bank, address account) external returns (bool);

    function decidePendingTransfer(TransferId id, TransferStatus status, string memory reason) external returns (bool);
}


interface ISoCashFXProvider {
    event CurrencyAccountSet(CCY indexed ccy, ISoCashAccount account);
    function setCurrencyAccount(CCY ccy, ISoCashAccount account) external;

    function setFXRateSource(CCY base, CCY quote, string calldata source) external;
    function getFXRateSource(CCY base, CCY quote) external view returns (string memory);

    function setRateSigner(address signer) external;
    function getRateSigner() external view returns (address);

    function hashOfFXRate(FXRate memory rate) external view returns (bytes32);
    function verifyFXRate(FXRate memory rate, bytes memory signature) external view returns (bool);
    event FXSettlement(ISoCashAccount indexed from, ISoCashAccount indexed to, uint256 amount, uint256 rate);
    function settlement(RecipentInfo calldata from, RecipentInfo calldata to, uint256 amount, FXRate calldata rate, bytes calldata signature, string calldata details) external returns (bool);
}