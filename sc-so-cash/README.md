# Documenting the so|cash smart contract version 2.0 

This version provide a revised way for the correspondent banking relation, using an external, shared referential

## Concepts

* Bank module (or simply bank) is a smart contract that represents all liabilities of a bank in a given currency toward its customers.
* Bank Account is a smart contract that represents a customer account in a bank module.
* Correspondent is a bank that is designed (identified) by a bank to be used to reach itself for a given currency. A bank records its correspondents in the referential.
* SSI referential an account or an address in an ERC20 token that is designed by a bank to tell other where it expects to be paid in a given currency to process an incoming payment. A bank records its SSI referentials in the referential.
* Root referential is a smart contract that is global and created by an initial actor (such as BIS).
* Country referential is a smart contract that is created by a country authority (AMF, FCA, etc.) that is registered into the root referential against a country code and in which banks are allowed to register their bank modules, SSI referentials and correspondents.
* BankIdentifier is a structure that identify a bank in a country referential. It contains the currency code of the country with which it is registered and the various codes that identify the bank in the country. For instance in France, the first code is the "bank code" and the second code is the "branch code". These codes are 10 chars wide maximum.

## Creating a bank module

The smart contract SoCashBank is relatively big and had to be split with libraries. These libraries must be deployed before the bank module itself. The libraries are:
- IBANCalculator: a library that provides IBAN calculation and validation functions
- SharedFunctions: a library that provides utility functions
- PaymentEngine: a library that provides business logic for payments and some IBAN decoding

When using the `@saturn-chain/smart-contract` library, the deployment of the libraries is done automatically once but the deployed address is kept in memory only so at next restart of the program libraries will be redeployed. So keep this in a separarate storage if you want to reuse the lib accross executions. This can be achieved with an undocumented feature of the library : `allContracts.get("LIBName").deployedAt = "0x1234567890abcdef1234567890abcdef12345678";`

When deploying the bank module contract, the following parameters must be provided:
- `address rootReferential`: the address of the root referential. 
- `BIC bic`: the BIC of the bank
- `BankIdentifier bankIdentifier`: the bank identifier of the bank
- `string ccy`: the currency code of the bank
- `uint decimals`: the number of decimals of the currency

The autority of the country of the bank should have delivered a bank code, used as the first code in the bank identifier. The authority should have linked a wallet of the bank to the bank code in the country referential with `countryRef.setBankController(...)`.

With this wallet the bank can now register its bank module, SSI and correspondent in the country referential.

To register the bank module in the country referential, the bank must call the `countryRef.setBankModule(codes, ccy, bankModule)` function. The `codes` parameter is in the bank identifier structure and the `bankModule` parameter is the address of the bank module. This allows other banks (and participants) to find the smart contract of the bank by its codes and currency.

## Opening a nostro account with another bank

When a bank wants to open a nostro account with another bank there are 2 technical options. Either the nostro is a so|cash compatible account with another bank or it is a balance in an ERC20 token (such as a stablecoin).

Once such an account is opened it must be declared in the bank module with the `bank.registerNostroAccount(BankAccount account)` function. The `account` parameter is a structure with 3 fields: `model` to designate whether it is a so|cash account or an ERC20 token, `bank` to designate the address of the bank (or the ERC20 token) and `account` to designate the address of the account in the bank (or the address of the balance in the ERC20 token). Such registration allows the bank to keep track of the balance of the account and to use it for payments.

If this nostro account is to be used as a SSI to receive funds from other banks when processing payments then it must be registered in the referential with the `countryRef.setSSI(codes, ccy, BankAccount account)`. For the moment a single SSI by currency is allowed.

Note that the standard does not take consideration of the nature of the money flowing in these nostro account. But one can realize that the bank holding the nostro account can be a central bank so money on such account can be central bank money or wCBDC.

## Registering a correspondent bank

When a bank wants to register a correspondent bank it must call the `countryRef.addCorrespondent(codes, ccy, BankIdentifier bankIdentifier)` function on the country referential. This allows the bank to declare that bank accepts to receive payment instructions from the correspondent. The correspondent bank must have a bank module registered in the same country referential.

## Opening a nostro to another bank

When a bank opens an account to another bank, as a nostro, there is a special action to be done to enable the bank to receive advice when its account is modified: The bank module of the client bank should be linked as an attribute of the bank account with `account.setAttributeAddr("soCashBank", bankModule)`. This allows the holding bank to know who to connect with to send advice.

## Processing an outgoing payment

A typical payment involves an instruction to debit an account in a bank and a beneficiary that should receive the amount. Such beneficiary can be in the same bank, in a bank where the bank has a nostro account or in a bank that is a correspondent of the bank or in a bank that is not a correspondent of the bank. Let's explore these cases.
The beneficiary is represented either by a bank account address of by an IBAN, or only a BIC if the beneficiary is the bank.

In all cases, the first step is to identify the bank where the beneficiary has its account. The result is a bank identifier, the bank module address and the account address. This is done with the `PaymentEngine.getTargetBankIdentifier(recipient)` function.

### Case O1: the beneficiary is in the same bank as the payer
* Debit payer account
* Credit beneficiary account
* 
### Case O2: the beneficiary is a BIC of the same bank
* Debit payer account

There is no credit because accountingwise reducing the liability is done against a payable account that justify this debit (for instance a loan repayment).

### Other cases common steps
The bank identifier of the beneficiary account is processed to identify what should be the next bank to talk to and if this bank has SSI.

As a result, the process retrieve the bank identifier of the next bank to talk to, the address of this bank module and the ssi account to use to send funds to it. This is done with the `PaymentEngine.resolveCorrespondentBank(bankIdentifier)` function.

Then, the process checks whether the paying bank has a so|cash nostro within that next bank.

### Case O3: the beneficiary is in a bank where the payer's bank has a nostro account and the balance is sufficient
* Debit payer account
* Make a transfer from the nostro to the beneficiary account (outgoing payment process)

### Case O4: the next bank has its SSI with the paying bank
* Debit payer account
* Credit the SSI account of the next bank
* Transfer the payment flow to the next bank (incoming payment process)

### Case O5: the paying bank has a nostro in the same bank as the next bank SSI
Note that the nostro account and SSI can be addresses in an ERC20 token.
* Debit payer account
* Transfer from the payer's bank nostro to the next bank SSI account
* Transfer the payment flow to the next bank (incoming payment process)

### Other cases: 
If there is no SSI for the next bank, an error is emitted.
In other cases nothing happen.

## Processing an incoming payment from another bank

This situation happens when a correspondent bank has routed the payment to the bank (cases O4 and O5 above). The receiving bank is expected to have been paid to its SSI account. This is controlled by getting the actual balance of the SSI account and comparing it with the last known balance of the SSI account (nostro). If the balance has not increased by the amount the payment is rejected.

Similar to an outgoing payment, the beneficiary is represented either by a bank account address of by an IBAN, or only a BIC if the beneficiary is the bank. The process first identifies the bank where the beneficiary has its account : bank indentifier.

### Case I1: the beneficiary is in the receiving bank
* Credit beneficiary account

There is no debitting, because the money has been received in another bank, so accountingwise is is a debit of the asset.

### Case I2: the beneficiary is a BIC of the receiving bank

No entry, because the money has been received in another bank, so accountingwise is is a debit of the asset against a credit of a payable.

### Other cases common steps
The bank identifier of the beneficiary account is processed to identify what should be the next bank to talk to and if this bank has SSI. This is the same logic as in the outgoing payment.

### Case I3: the beneficiary is in a bank where the receiving bank has a nostro account and the balance is sufficient
* Make a transfer from the nostro to the beneficiary account (outgoing payment process)

### Case I4: the next bank has its SSI with the receiving bank
* Credit the SSI account of the next bank
* Transfer the payment flow to the next bank (incoming payment process)

### Case I5: the receiving bank has a nostro in the same bank as the next bank SSI
Note that the nostro account and SSI can be addresses in an ERC20 token.
* Transfer from the receiving bank nostro to the next bank SSI account
* Transfer the payment flow to the next bank (incoming payment process)

### Other cases: 
If there is no SSI for the next bank, an error is emitted.
In other cases nothing happen.

## Illustration case

Let's consider a client of bank A that wants to pay a beneficiary in bank D. Bank D has a nostro with the central bank CB. The Bank D has Bank C as correspondent that also has an account with CB. Bank B has a nostro with Bank C and another with Bank A, marked as SSI.

The execution of the payment is as follows as a single operation:
* Bank A debits the client account
* Bank A credit the Bank B account
* Bank A instruct Bank B to transfer the amount to the beneficiary
* Bank B instruct bank C to transfer the amount from its nostro to the beneficiary
* Bank C debit the Bank B account
* Bank C transfer the amount from its nostro in CB to the CB account of Bank D
* Bank C instruct Bank D to pay the beneficiary
* Bank D credit the beneficiary account

```pre
  ┌────────────┐               ┌────────────┐             ┌─────────────┐                          ┌──────────────┐  
  │   Bank A   │               │   Bank B   │             │   Bank C    │                          │   Bank D     │  
  │            ┼───────────────►            ├─────────────►             ├──────────────────────────►              │  
  │ Client     │               │            │             │  Bank B     │                          │   Mint       │  
  │    │       │               │            │             │    │        │      ┌─────────────┐     │     │        │  
  │    │       │               │            │             │    ▼        │      │   Central   │     │     ▼        │  
  │    ▼       │               │            │             │   Burn      ├──────►    Bank     │     │   Benef      │  
  │ Bank B     │               │            │             │             │      │             │     │              │  
  └────────────┘               └────────────┘             └─────────────┘      │  Bank C     │     └──────────────┘  
                                                                               │     │       │                       
                                                                               │     │       │                       
                                                                               │     ▼       │                       
                                                                               │  Bank D     │                       
                                                                               └─────────────┘                       
```