// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import {ISoCashBankExternal} from "@so-cash/sc-so-cash/src/intf/so-cash-bank.sol";
import "../intf/so-cash-referential.sol";

contract RootReferential is ISoCashGlobalReferential {
  mapping(bytes2 => ISoCashCountryReferential) public countries;

  // ResolveData of BankIdentifier
    struct VisitedAndParentIndex {
      bool visited;
      uint256 parent;
    }
    struct ResolveData {
      BankIdentifier[] items;
      uint256[] parents;
      bytes32[] visitedHashes;
      uint256 visitedLength;
      // indexes of the queue front and back
      uint256 front;
      uint256 back;
    }

    function hashOfBank(BankIdentifier memory bankId) internal pure returns (bytes32) {
      bytes32 hash = keccak256(abi.encodePacked(bankId.country, bankId.codes));
      return hash;
    }

    function addVisited(ResolveData memory queue, bytes32 hash) internal pure returns (ResolveData memory) {
      queue.visitedHashes[queue.visitedLength++] = hash;
      require(queue.visitedLength < queue.visitedHashes.length, "ResolveData visited queue is full");
      return queue;
    }

    function isVisited(ResolveData memory queue, bytes32 hash) internal pure returns (bool) {
      for (uint i = 0; i < queue.visitedLength; i++) {
        if (queue.visitedHashes[i] == hash) {
          return true;
        }
      }
      return false;
    }

    function enqueue(ResolveData memory queue, BankIdentifier memory item, uint256 parentIndex) internal pure returns (ResolveData memory){
        queue.items[queue.back] = item;
        queue.parents[queue.back] = parentIndex;
        queue.back++;
        require(queue.back < queue.items.length, "ResolveData queue is full");
        return queue;
    }

    function dequeue(ResolveData memory queue) internal pure returns (ResolveData memory, BankIdentifier memory, uint256 index) {
        require(queue.front < queue.back, "ResolveData is empty");
        BankIdentifier memory item = queue.items[queue.front];
        queue.front++;
        return (queue, item, queue.front - 1);
    }

    function isEmpty(ResolveData memory queue) internal pure returns (bool) {
        return queue.front >= queue.back;
    }


  // No access right control in this version. This is bad for production
  function setCountry(ISoCashCountryReferential countryContract) external override {
    bytes2 country = countryContract.countryCode();
    countries[country] = countryContract;
    emit CountrySet(country, countryContract);
  }

  function getCountry(bytes2 country) external view override returns (ISoCashCountryReferential) {
    return countries[country];
  }

  function createRouteFromResolveData(ResolveData memory data, uint256 fromIndex) internal pure returns (BankIdentifier[] memory) {
    // first we count the number of items in the route starting from the last item that is the from bank
    uint256 count = 0;
    uint256 index = fromIndex; // this must the the index of the from bank
    while (index != 0) {
      count++;
      index = data.parents[index];
    }
    count += 1; // to add the first item that is the target bank

    // then we create the route array
    BankIdentifier[] memory route = new BankIdentifier[](count);
    index = fromIndex;
    for (uint i = 0; i < count; i++) {
      route[i] = data.items[index];
      index = data.parents[index];
    }
    return route;
  }

  function resolveRoute(bytes3 currency, BankIdentifier memory from, BankIdentifier memory target) external view override returns (bool resolved, BankIdentifier[] memory route) {
    (resolved, route, ) = this.resolveRoute2(currency, from, target);
  }
  function resolveRoute2(bytes3 currency, BankIdentifier memory from, BankIdentifier memory target) external view returns (bool resolved, BankIdentifier[] memory route, ResolveData memory debug) {
    uint256 maxNodes = 30;
    uint256 maxHops = 10;
    uint256 hops = 0;
    ResolveData memory r = ResolveData(new BankIdentifier[](maxNodes), new uint256[](maxNodes), new bytes32[](maxNodes), 0, 0, 0);
    // resolve from the target bank to the instructing bank because correspondents of a target are the route to the target
    r = enqueue(r, target, 0);
    BankIdentifier memory current;
    bytes32 currentHash;
    uint256 currentIndex;
    bytes32 fromHash = hashOfBank(from);
    while (!isEmpty(r) && hops < maxHops) {
      // get the next bank, the head of index is incremented (r.start)
      (r, current, currentIndex) = dequeue(r);
      currentHash = hashOfBank(current);

      // check if the current bank is the target, then we have reach an end
      if (currentHash == fromHash) return (true, createRouteFromResolveData(r, currentIndex), r);

      if (!isVisited(r, currentHash)) {
        r = addVisited(r, currentHash);
        // list the correspondent banks of the current node
        ISoCashCountryReferential country = this.getCountry(current.country);
        require(address(country) != address(0), "country not found");
        BankIdentifier[] memory correspondents = country.getCorrespondentBanks(current.codes, currency);
        hops++;
        for (uint i = 0; i < correspondents.length; i++) {
          // potentially here we can check if the correspondent has liquidity
          // the problem is that there are multiple place where the correspondent can get its liquidity
          // so we can't check it here for now
          r = enqueue(r, correspondents[i], currentIndex);
        }
      }
    }
    return (false, new BankIdentifier[](0), r);
  }
}

contract CountryReferential is ISoCashCountryReferential, Ownable {
  // event debug(string message, CodeType code);

  mapping(address => mapping(CodeType => bool)) public bankControllers;
  // index(codes) => currency => bank module
  mapping(bytes32 => mapping(bytes3 => ISoCashBankExternal)) public bankModules;
  // index(codes) => currency => bank identifier
  mapping(bytes32 => BankIdentifier) public bankIds;
  // index(codes) => currency => correspondent bank index
  mapping(bytes32 => mapping(bytes3 => bytes32[])) public correspondentBanks;
  // index(codes) => currency => SSI (for the moment only one SSI per bank/currency)
  mapping(bytes32 => mapping(bytes3 => BankAccount)) public SSIs;

  bytes2 public countryCode;
  constructor(bytes2 _countryCode) Ownable() {
    countryCode = _countryCode;
  }

  // TODO: protect this function with access control
  function setBankController(CodeType bankCode, address controller) external override {
    bankControllers[controller][bankCode] = true;
    emit BankControllerSet(bankCode, controller, true);
  }
  // TODO: protect this function with access control
  function unsetBankController(CodeType bankCode, address controller) external override {
    bankControllers[controller][bankCode] = false;
    emit BankControllerSet(bankCode, controller, false);
  }
  function isBankController(CodeType bankCode, address controller) external view override returns (bool) {
    return bankControllers[controller][bankCode];
  }

  modifier onlyBankController(CodeType[] memory codes) {
    require(codes.length > 0, "At least one code is required");
    require( this.owner() == msg.sender 
      || this.isBankController(codes[0], msg.sender),
       "Only bank controller can call this function");
    _;
  }

  modifier onlyBankController1(CodeType bankCode) {
    require( this.owner() == msg.sender 
      || this.isBankController(bankCode, msg.sender),
       "Only bank controller can call this function");
    _;
  }

  function copyCodes(CodeType[] memory codes, uint from, uint to) internal pure returns (CodeType[] memory) {
    if (to == 0) to = codes.length;
    CodeType[] memory _codes = new CodeType[](to-from);
    uint j = 0;
    for(uint i=from; i<to; i++) {
      // emit debug(string(abi.encodePacked("copy ", bytes1(uint8(48+i)))), codes[i]);
      _codes[j++] = codes[i];
    }
    return _codes;
  }

  // create a bytes32 with the hash of the country and all codes in sequence
  function _index(CodeType[] memory codes) internal view returns (bytes32) {
    require(codes.length > 0, "At least one code is required");
    bytes32 index = keccak256(abi.encodePacked(countryCode));
    for (uint i = 0; i < codes.length; i++) {
      index = keccak256(abi.encodePacked(index, codes[i]));
    }
    return index;
  }

  /** 
    * @dev Set the bank module for a bank identified by the codes and currency
    * @param codes The bank codes. ATTENTION: The codes must be sent as an array of Buffer of exactly 10 bytes even of the code is shorter
    * @param currency The currency code sent as a Buffer of 3 bytes
    * @param bankModule The bank module to set
   */
  function setBankModule(CodeType[] calldata codes, bytes3 currency, ISoCashBankExternal bankModule) onlyBankController(codes) public override {
    
    bankModules[_index(codes)][currency] = bankModule;
    emit BankModuleSet(codes[0], codes[1:], currency, bankModule);
  }

  /**
    * @dev Add a correspondent bank for a bank identified by the codes and currency
    * @param codes The bank codes. ATTENTION: The codes must be sent as an array of Buffer of exactly 10 bytes even of the code is shorter
    * @param currency The currency code sent as a Buffer of 3 bytes
    * @param correspondent The correspondent bank to set. In this structures the codes must be sent as an array of Buffer of exactly 10 bytes even of the code is shorter
   */
  function addCorrespondent(CodeType[] calldata codes, bytes3 currency, BankIdentifier calldata correspondent) onlyBankController(codes) public override {
    bytes32 corrId = _index(correspondent.codes);
    // save the correspondent bank info in the bankIds if it is not already saved
    if( bankIds[corrId].country == 0 ) bankIds[corrId] = correspondent;
    correspondentBanks[_index(codes)][currency].push(corrId);
    emit CorrespondentBankChange(codes[0], codes[1:], currency, correspondent, true);
  }

  function delCorrespondent(CodeType[] calldata codes, bytes3 currency, BankIdentifier calldata correspondent) onlyBankController(codes) public override {
    bytes32 corrId = _index(correspondent.codes);
    bytes32[] storage records = correspondentBanks[_index(codes)][currency];
    for (uint i = 0; i < records.length; i++) {
      if (records[i] == corrId) {
        if (i < records.length - 1) { // if not the last element
          records[i] = records[records.length - 1]; // move the last element to the position of the element to delete
        }
        records.pop(); // remove the last element
        emit CorrespondentBankChange(codes[0], codes[1:], currency, correspondent, false);
        return;
      }
    }
  }


  function setFXProvider(CodeType bankCode, ISoCashFXProvider fxProvider) onlyBankController1(bankCode) public override {
    // no storage, just raise the event
    emit FXProviderSet(bankCode, fxProvider, true);
  }
  function unsetFXProvider(CodeType bankCode, ISoCashFXProvider fxProvider) onlyBankController1(bankCode) public override {
    // no storage, just raise the event
    emit FXProviderSet(bankCode, fxProvider, false);
  }


  function setSSI(CodeType[] calldata codes, bytes3 currency, BankAccount calldata account) onlyBankController(codes) public override {
    SSIs[_index(codes)][currency] = account;
    emit SSIChange(codes[0], codes[1:], currency, account);
  }

  function getBankModule(CodeType[] memory codes, bytes3 currency) external view override returns (ISoCashBankExternal) {
    return bankModules[_index(codes)][currency];
  }

  function getCorrespondentBanks(CodeType[] memory codes, bytes3 currency) external view override returns (BankIdentifier[] memory correspondents) {
    bytes32[] storage records = correspondentBanks[_index(codes)][currency];
    correspondents = new BankIdentifier[](records.length);
    for (uint i = 0; i < records.length; i++) {
      correspondents[i] = bankIds[records[i]];
    }
    return correspondents;
  }

  function isCorrespondent(CodeType[] memory codes, bytes3 currency, BankIdentifier memory correspondent) external view override returns (bool) {
    bytes32 corrId = _index(correspondent.codes);
    bytes32[] storage records = correspondentBanks[_index(codes)][currency];
    for (uint i = 0; i < records.length; i++) {
      if (records[i] == corrId) return true;
    }
    return false;
  }

  function getSSI(CodeType[] memory codes, bytes3 currency) external view override returns (BankAccount memory account) {
    return SSIs[_index(codes)][currency];
  }
}