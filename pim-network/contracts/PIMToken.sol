// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/// @notice PIM ERC-20 with a fixed max supply of 10,000,000 PIM.
/// @dev `mint(amount)` is open (mints to msg.sender) but still capped.
contract PIMToken is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 10_000_000 ether;

    constructor() ERC20('PIM Token', 'PIM') Ownable(msg.sender) {}

    function maxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    function mint(uint256 amount) external {
        _mintCapped(msg.sender, amount);
    }

    function mintTo(address to, uint256 amount) external onlyOwner {
        _mintCapped(to, amount);
    }

    function _mintCapped(address to, uint256 amount) internal {
        require(to != address(0), 'PIM: zero address');
        require(amount > 0, 'PIM: amount=0');
        require(totalSupply() + amount <= MAX_SUPPLY, 'PIM: max supply reached');
        _mint(to, amount);
    }
}
