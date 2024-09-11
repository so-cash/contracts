# Source code for so|cash smart contracts

This documents the version 1.0.0 of the so|cash smart contracts.
This is not intended to be the final version but a starting point for the development of the so|cash standard.

For the full documentation, please wait a bit... or "read the code" and unit tests.   
In particular, we recommend reviewing the [unit testing](https://github.com/so-cash/contracts/tree/main/tests) and the smart contracts [interfaces](https://github.com/so-cash/contracts/tree/main/src/intf) before looking into the implementation.   
Note the following reading :
* [preparing smart contracts](https://github.com/so-cash/contracts/blob/1a63fda2f2f272e36100d082726bf08cd3567ceb/tests/so-cash-prepare.ts#L13): `prepareContracts()` function to deploy a minimum setup for testing
* [Use the contracts from a back office point of view](https://github.com/so-cash/contracts/blob/1a63fda2f2f272e36100d082726bf08cd3567ceb/tests/bo-actions.spec.ts#L9): Several unit testing useful to review
* [Peform transfers between accounts](https://github.com/so-cash/contracts/blob/1a63fda2f2f272e36100d082726bf08cd3567ceb/tests/interbank-actions.spec.ts#L11): Explore several transfer scenarios

## Getting Started (for developpers)

Any issue or question can be addressed to the so|cash team ussing the issues tab in the github repository.

### Prerequisites

To use this repo and get ready with the smart contracts you will need:
* an EVM compatible blockchain (e.g. Ethereum, Polygon ...). We recommend the PoCR testnet ([Kerleano](https://github.com/ethereum-pocr/kerleano)) where many tests have been implemented.
* Solidity compiler (solc) version 0.8.17.
* Node.js and npm.

### Installation and Build

1. Clone the repo in your local machine:
   ```sh
   git clone git@github.com:so-cash/contracts.git
   ```
2. Install the dependencies:
   ```sh
   npm install
   ```
3. Compile the contracts:
   ```sh
   npm run build
   ```
   This will generate the compiled contracts in `./build` folder. In this folder a single `combined.json` file will be generated containing all the contracts abi, runtime bytecode and deploy bytecode. 

   The compilation is done using the `solc` compiler with the following command line:
   ```sh
   $SOLC -o build --optimize --combined-json abi,bin,bin-runtime --overwrite --base-path . --include-path ./node_modules src/*/*.sol
   ```
   where `$SOLC` is the path to the solc compiler.

   You can obviouly use your preferred framework to compile the contracts such as `truffle` or `hardhat`.

   The `combined.json` file is used by the `@saturn-chain/smart-contract` library that is used in the `index.js` and the unitary tests.

   If you have difficulties in the building you can get the compiled contracts from the `build` folder of the repository directly.

### Unitary Tests and documentation

The unit testing are in `tests` folder. You can run the tests with:
```sh
npm run test
```
Or uning VS Code.

Note the tests are written using the `mocha` framework and the `chai` assertion library in TypeScript.

We recommend using the unit testing to understand the contracts and how to use them.

In particular, refer to the `prepareContracts()` function in the `tests/so-cash-prepare.ts` file to see the basic deployments of bank modules, accounts and inter bank correspondents relationship.

### Deployment sequence and basic usage

In order to get started with a minimal so|cash bank module and one bank account, you have to perform the following steps (**pseudo code** for simplicity - see the unit tests for more details):

The following code assumes that the smart contracts deployment and transactions executions are performed using a wallet with enough gas and connected to the EVM blockchain.

```typescript
// Load the compiled contracts from the combined.json file
import contracts from './build/index.js';

// deploy the sharable contract to manage IBAN
const iban = await contracts.get("IBANCalculator").deploy();
const [bic, bankCode, branchCode, ccy, decimals] = [
  "AGRIFRPP", "12345", "67890", "EUR", 2
];
// deploy the bank module for the EUR currency, the sole owner is the wallet that deploys it, assumed to be the back office wallet of the bank.
const eurModule = await contracts.get("SoCashBank").deploy(bic, bankCode, branchCode, ccy);

// deploy the bank account for a customer
const account = await constracts.get("SoCashAccount").deploy("AccountID");
// Give the ownership of the new smart contract to the EUR Bank module
await account.transferOwnership(eurModule.deployedAt);
// Enlist the account in the EUR bank module, making it a EUR account for that client in that bank
await eurModule.registerAccount(account.deployedAt);
```

To credit the account, using the wallet of the bank back office and check the balance:
```typescript
// Credit the account with 1 000.00 EUR (note the amount is in cents)
await eurModule.credit(account.deployedAt, 1000 * 100);
// Check the balance of the account
const balance = await eurModule.fullBalanceOf(account.deployedAt);
console.log("Account balance: EUR ", balance / 100);
```

To get the IBAN, name, account number, balance and ERC20 fields of the account:
```typescript
const iban = await account.iban();
const name = await account.name();
const number = await account.accountNumber();
const balance = await account.fullBalance();

const currency = await account.symbol();
const decimals = await account.decimals();
// get the positive part balance in the smallest unit of the currency ignoring the provided address
const unsignedBalance = await account.balanceOf(anyAddress);
// The total supply is the same as the balance of the account. Note that the bank module also has a total supply that is the sum of all the balances of the accounts.
const unsignedBalance2 = await account.totalSupply();
```

To enable alternative wallet to operate transfer on the account, call the whilelist or approve functions with the back office wallet:
```typescript
const wallet = "0x1234567890123456789012345678901234567890";
const thirdPartyContract = "0xabcdabcdabcdabcdabcdabcdabcdabcdabcdabcd";
// allow the wallet and the third party contract to operate on the account
await account.whitelist(wallet);
await account.whitelist(thirdPartyContract);
// approve the third party contract to perform a single transfer of 100.00 EUR using the standard ERC20 api
await account.approve(thirdPartyContract, 100 * 100);
```

Assuming you have a second account `account2` in the same or another bank module, you can transfer money from `account` to `account2` with an allowed wallet:
```typescript
// Transfer 100.00 EUR from account to account2 using ERC20 api
await account.transfer(account2.deployedAt, 100 * 100);
// Transfer 100.00 EUR from account to account2 using ERC20 transferFrom allowance
await account.transferFrom(account.deployedAt, account2.deployedAt, 100 * 100);
// Transfer 100.00 EUR from account to account2 using ISoCashAccount api (cover both cases above)
const recipient = new RecipientInfo(account2.deployedAt, "", ""); // no BIC or IBAN when the address of the beneficiary is provided
await account.transferEx(recipient, 100 * 100, "Transfer description");
```

### Playing with existing deployed contracts
In the ([Kerleano](https://github.com/ethereum-pocr/kerleano)) network ([see access here](https://chainlist.org/chain/1804)), the so|cash contracts are deployed for 2 banks. 

**Bank 1**: [0x498a4f1408e1831b4ba8dc4d915f73fb85096037](https://ethereum-pocr.github.io/explorer/kerleano/account/0x498a4f1408e1831b4ba8dc4d915f73fb85096037)
* account 1: [0xf5b23539a6edd450bea0b4638c125889a7c68071](https://ethereum-pocr.github.io/explorer/kerleano/account/0xf5b23539a6edd450bea0b4638c125889a7c68071)
* account 2: [0x9c2e99ec84f235a73dab60aa6a40afae248c5d69](https://ethereum-pocr.github.io/explorer/kerleano/account/0x9c2e99ec84f235a73dab60aa6a40afae248c5d69)

**Bank 2**: [0xa701b6004a2e985225384320979d57c5e708d991](https://ethereum-pocr.github.io/explorer/kerleano/account/0xa701b6004a2e985225384320979d57c5e708d991)
* account 3: [0x6fca9b7e91835fdb02a085919ca012fc851b29e4](https://ethereum-pocr.github.io/explorer/kerleano/account/0x6fca9b7e91835fdb02a085919ca012fc851b29e4)
* account 4: [0xa6a803733388452d65974cb3da0b13e7c3f5d36e](https://ethereum-pocr.github.io/explorer/kerleano/account/0xa6a803733388452d65974cb3da0b13e7c3f5d36e)

You can use the e-banking interface to view the account statment at https://so-cash.github.io/e-banking/accounts/0xf5b23539a6edd450bea0b4638c125889a7c68071, replacing the account address by the one you want to see.

To be able to perform operations you need to have a wallet that has been approved or whitelisted by the bank. Contact us via the issue if this is of interest to you.
