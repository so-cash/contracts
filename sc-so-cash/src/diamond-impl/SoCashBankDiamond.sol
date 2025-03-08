// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

import {IDiamondBase, DiamondBase} from "@fever-tokens/diamond/src/proxy/diamond/base/DiamondBase.sol";
import {IDiamondWritable, DiamondWritableInternal} from "@fever-tokens/diamond/src/proxy/diamond/writable/DiamondWritable.sol";
import {FacetCut} from "@fever-tokens/diamond/src/proxy/diamond/writable/IDiamondWritableInternal.sol";
import {DiamondReadable} from "@fever-tokens/diamond/src/proxy/diamond/readable/DiamondReadable.sol";
import {InitializableInternal} from "@fever-tokens/diamond/src/initializable/InitializableInternal.sol";
import {DiamondReadableFaceCut, DiamondWritableFaceCut} from "@fever-tokens/diamond/src/proxy/Proxy.sol";

import {OwnableStorage} from "@fever-tokens/diamond/src/ownable/OwnableStorage.sol";
import {ReentrancyGuardStorage} from "@fever-tokens/diamond/src/security/ReentrancyGuardStorage.sol";

import {
  ISoCashGlobalReferential, 
  ISoCashCountryReferential,
  BankIdentifier
  } from "@so-cash/sc-so-cash-ref/src/intf/so-cash-referential.sol";
import {
  CCY, IBAN, BIC
  } from "../intf/so-cash-types.sol";
// these imports are required to ensure compiler optimization does not ignore these contracts
import {Ownable} from "@fever-tokens/diamond/src/ownable/Ownable.sol";

import {BankBalanceManagementStorage} from "./facets/bank-balances-mgmt/BankBalanceManagementStorage.sol";
import {BankERC20MetadataStorage} from "./facets/bank-erc20/BankERC20MetadataInternal.sol";
import {BankIdentityStorage} from "./facets/bank-identity/BankIdentityStorage.sol";
import {BankNostroManagementStorage} from "./facets/bank-nostros-mgmt/BankNostroManagementStorage.sol";
import {BankTransferManagementStorage} from "./facets/bank-transfers-mgmt/BankTransferManagementStorage.sol";
import {HTLCPaymentStorage} from "./facets/htlc-payment/HTLCPaymentStorage.sol";
import {WhitelistedSendersInternal} from "./facets/whitelisted-senders/WhitelistedSendersInternal.sol";

contract SoCashBankDiamond is IDiamondBase, DiamondBase, DiamondWritableInternal {
    constructor(
        address _diamondReadablePackage,
        address _diamondWritablePackage,
        // the initialize() function selector followed by all its data. It will be transmitted as-is to the DiamondWritableInternal._initialize() function
        bytes memory _initData
    ) {
        // diamond cut
        FacetCut[] memory facetCuts = new FacetCut[](2);

        facetCuts[0] = DiamondReadableFaceCut.cuts(_diamondReadablePackage);
        facetCuts[1] = DiamondWritableFaceCut.cuts(_diamondWritablePackage);
        _diamondCut(facetCuts, _diamondWritablePackage, _initData);
    }

    receive() external payable {}
}

contract SoCashBankDiamondReadable is DiamondReadable {
}

contract SoCashBankDiamondWritable is InitializableInternal, DiamondWritableInternal, WhitelistedSendersInternal {
    function initialize(
        ISoCashGlobalReferential routingRef, 
        BIC pBic, 
        BankIdentifier memory pId, 
        CCY currency, 
        uint8 nDecimals
    ) external initializer {
      ReentrancyGuardStorage.__init();
      OwnableStorage.__init(msg.sender);
      BankBalanceManagementStorage.__init();
      BankERC20MetadataStorage.__init(
        string(abi.encodePacked(pBic)), 
        string(abi.encodePacked(currency)),
        nDecimals);
      BankIdentityStorage.__init(routingRef, pBic, pId);
      BankNostroManagementStorage.__init();
      BankTransferManagementStorage.__init();
      HTLCPaymentStorage.__init();
    }

    function diamondCut(
        FacetCut[] calldata facetCuts,
        address target,
        bytes calldata data
    ) external onlyWhitelisted { 
        _diamondCut(facetCuts, target, data);
    }
}