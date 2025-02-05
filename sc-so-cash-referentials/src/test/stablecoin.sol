// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Stablecoin is ERC20, Ownable {
  uint8 private _decimals = 18;
  constructor(string memory name, string memory symbol, uint256 initialQty, uint8 __decimals) ERC20(name, symbol) {
    _decimals = __decimals;
    _mint(msg.sender, initialQty * 10 ** _decimals);
  }

  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) public onlyOwner {
    _burn(from, amount);
  }
}