// SPDX-License-Identifier: MIT
// CACIB Contracts v2.0.0

pragma solidity ^0.8.17;

import {
  ISoCashCountryReferential, 
  ISoCashCountryManager, 
  BankIdentifier} from "../intf/so-cash-referential.sol";
import {PathFinderStorage} from "./PathFinderStorage.sol";

contract PathFinderInternal {
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

  function resolveRoute2(ISoCashCountryManager self, bytes3 currency, BankIdentifier memory from, BankIdentifier memory target) external view returns (bool resolved, BankIdentifier[] memory route, ResolveData memory debug) {
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
        ISoCashCountryReferential country = self.getCountry(current.country);
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

