# This file is for collecting thoughts and possible solutions for routing mechanism between so|cash smart contracts.

## Currently, 

to identify the beneficiary account and its bank, the debtor bank uses either the beneficiary account address or an IBAN.

When an address is used, the so|cash account behind this address should expose the `bank()` function to return the `ISoCashBank` that manages the account. And the debtor bank smart contract checks if the beneficiary's bank is in its list of correspondent. Else it will reject the transaction.

When an IBAN is used, the debtor bank smart contract decodes the IBAN (FR only for now) and finds the bank code and the branch code. From these it uses its internal mapping to identify the address of the `ISoCashBank` that should be managing the account and asks it to give the `ISoCashAccount` address corresponding to the account number. Then it proceeds as if the address was provided (as above).

## Problems

* If the beneficiary account is not in a bank that is a correspondent of the debtor bank, the transaction is rejected. There is no way to route the transaction to the correct bank.
* Only french IBANs are supported for now. 


## Possible logic of resolution

### The debtor bank receives an `ISoCashAccount` address as beneficiary

The `ISoCashBank` can be resolved by the `bank()` function of the `ISoCashAccount` contract. 
If the bank is not a correspondent of the debtor bank, the debtor should find a correspondent bank that can route the transaction to the correct bank.

Assuming we have a global mapping managed by each bank where it exposes from what bank it can be reached.

__For instance:__
To reach (EUR, FR, bankCode1, BranchCode1) uses (ES, bankCode2, BranchCode2) 
To reach (USD, US, bankCode1, BranchCode1) uses (US, bankCode3, BranchCode3)
To reach (EUR, ES bankCode2, BranchCode2) uses (FR, bankCode4, BranchCode4)
Address of (EUR, FR, bankCode1, BranchCode1) is 0x1234
Address of (EUR, ES, bankCode2, BranchCode2) is 0x5678
Address of (USD, US, bankCode1, BranchCode1) is 0x9abc
Address of (EUR, FR, bankCode4, BranchCode4) is 0xdef0
Address of (USD, US, bankCode3, BranchCode3) is 0x4321

So the debtor bank can get the `codes()` from the beneficiary bank and loops thru the referential until it finds a bank that is a correspondent bank of the debtor bank to be able to send the transfer request. 

In pseudo code:
```js
function resolveNextCorrespondentBank(targetAccount: ISoCashAccount) {
  targetBank = targetAccount.bank();
  currency = targetBank.currency();
  codes = targetBank.codes();
  return resolveNextCorrespondentBankWithCodes(currency, codes);
}

function resolveNextCorrespondentBankWithCodes(currency, codes) {
  correspondentBank = null;
  maxHops = 10; // some parameter to consider
  hops = 0;
  
  while (hops < maxHops && correspondentBank == null) {
      theirCorrespondentBank = getCorrespondentBank(currency, codes); // using the mapping
      theirCorrespondentBankAddress = getAddressOf(theirCorrespondentBank); // using the mapping
      if (isOurCorrespondent(theirCorrespondentBankAddress)) {
          return theirCorrespondentBankAddress;
      }
      hops++;
  }
  return null;
}
```

### The debtor bank receives an IBAN as beneficiary

The debtor bank decodes the IBAN and finds the country, bank code and branch code. It then uses the same logic as above to find the next correspondent bank that can route the transaction to the correct bank using `resolveNextCorrespondentBankWithCodes()`

## Who manages the mapping?

In distributed ledger, the referential can be shared in a public contract where each bank can update its own mapping. But this needs to be organised in such a way that a bank can only updates its own mapping and not the mapping of another bank.

Currently, in France for instance, the bank code is delivered by the ACPR (Autorité de Contrôle Prudentiel et de Résolution). So we can imagine that the ACPR can create a record in the mapping for each bank and give the bank the right to update its own sub mapping (branch code, addresses ...) similar to the ENS model.

For instance a root ENS node that contains nodes for each ISO country code, managed by the institution of the country in charge of banks licences.

I find the ENS model a bit too complex for a first version. I will initiate with a simpler structure

`Root` contract that contains a mapping of country codes to `Country` contracts. Each `Country` implements a mapping of bank codes to a structure that will enables finding the mapping that the bank will setup.

The interfaces could look like

```solidity
interface ISoCashGlobalReferential {
    // set by a global administrator - future governance model to be defined to prevent centralisation
    function setCountry(bytes2 country, ISoCashCountryReferential countryContract) external;
    function getCountry(bytes2 country) external view returns (ISoCashCountryReferential);
}

interface ISoCashCountryReferential {
    // called only by the controller/owner of the country
    function setBankController(bytes calldata bankCode, address controller) external;
    
    // functions for the banks to setup its config. codes are one, tw oor possbly more codes to reach the bank (bank code, branch code ...)
    function setBankModule(bytes[] calldata codes, bytes3 currency, ISoCashBank bankModule) external;
    function addCorrespondent(bytes[] calldata codes, bytes3 currency, bytes2 country, bytes[] calldata correspondentBankCodes) external;

    // functions to resolve the routing
    function getBankModule(bytes[] calldata codes) external view returns (ISoCashBank);
    function getCorrespondentBank(bytes[] calldata codes, bytes3 currency) external view returns (bytes2 country, bytes[] memory cbCodes);
}
```