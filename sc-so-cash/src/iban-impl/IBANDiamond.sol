// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0
pragma solidity ^0.8.17;

/**
  * @title IBAN Diamond smart contract that allow the upgrade of the IBAN implementation per country code
 */

import {IDiamondReadable} from "@fever-tokens/diamond/src/proxy/diamond/readable/IDiamondReadable.sol";
import {IDiamondWritable} from "@fever-tokens/diamond/src/proxy/diamond/writable/IDiamondWritable.sol";
import {IProxy} from "@fever-tokens/diamond/src/proxy/IProxy.sol";
import {AddressUtils} from "@fever-tokens/diamond/src/utils/AddressUtils.sol";
import {DiamondReadableFaceCut, DiamondWritableFaceCut} from "@fever-tokens/diamond/src/proxy/Proxy.sol";
import {FacetCut} from "@fever-tokens/diamond/src/proxy/diamond/writable/IDiamondWritableInternal.sol";


import {IBANBaseStorage} from "./IBANBaseStorage.sol";
import {I_IBANService, CountryCode} from "./I_IBANService.sol";

contract IBANDiamond is I_IBANService {
  using AddressUtils for address;

  function _extractCountryCode(string memory iban) internal pure returns (CountryCode) {
    bytes memory b = bytes(iban);
    require(b.length >= 2, "Invalid IBAN size");
    uint16 code = (uint16(uint8(b[0])) << 8) | uint16(uint8(b[1]));
    return CountryCode.wrap(bytes2(code));
  }

  function _getFacet(CountryCode country) internal view returns (address) {
    return IBANBaseStorage.layout()._facets[country];
  }

  // Standard Diamond constructor so the libraries can handle this specific implementation
  constructor(
      address _diamondReadablePackage,
      address _diamondWritablePackage,
      // the initialize() function selector followed by all its data. It will be transmitted as-is to the DiamondWritableInternal._initialize() function
      bytes memory /*_initData*/
  ) {
      // diamond cut
      FacetCut[] memory facetCuts = new FacetCut[](2);

      facetCuts[0] = DiamondReadableFaceCut.cuts(_diamondReadablePackage);
      facetCuts[1] = DiamondWritableFaceCut.cuts(_diamondWritablePackage);
      // _diamondCut(facetCuts, _diamondWritablePackage, _initData);
  }

  receive() external payable {}

  function createIBAN(CountryCode country, string[] memory codes) external view override returns (string memory) {
    address facet = _getFacet(country);
    require(facet.isContract(), "Facet not found");
    return I_IBANService(facet).createIBAN(country, codes);
  }

  function decodeIBAN(string memory iban) external view override returns (bool valid, CountryCode country, string[] memory codes) {
    CountryCode c = _extractCountryCode(iban);
    address facet = _getFacet(c);
    require(facet.isContract(), "Facet not found");
    return I_IBANService(facet).decodeIBAN(iban);
  }
}

contract IBANDiamondReadable is IDiamondReadable {
  // NOT IMPLEMENTED YET
  function facets() external view override returns (Facet[] memory) {
    Facet[] memory result = new Facet[](0);
    IBANBaseStorage.Layout storage l = IBANBaseStorage.layout();
    l._facets; // to remove the pure warnign for now
    return result;
  }
  function facetFunctionSelectors(
        address facet
    ) external view override returns (bytes4[] memory selectors) {
    IBANBaseStorage.Layout storage l = IBANBaseStorage.layout();
    facet; // to remove the pure warnign for now
    l._facets; // to remove the pure warnign for now
    selectors = new bytes4[](0);
  }

  function facetAddresses()
      external
      view
      override
      returns (address[] memory addresses) {
    IBANBaseStorage.Layout storage l = IBANBaseStorage.layout();
    l._facets; // to remove the pure warnign for now
    addresses = new address[](0);
  }

  function facetAddress(
      bytes4 selector
  ) external view override returns (address facet) {
    IBANBaseStorage.Layout storage l = IBANBaseStorage.layout();
    l._facets; // to remove the pure warnign for now
    selector; // to remove the pure warnign for now
    return address(0);
  }
}

contract IBANDiamondWritable is IDiamondWritable {
  // NOT IMPLEMENTED YET
  function diamondCut(
      FacetCut[] calldata facetCuts,
      address target,
      bytes calldata data
  ) external override {
  }
}