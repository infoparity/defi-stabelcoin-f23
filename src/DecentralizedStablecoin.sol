// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStablecoin
 * @author infoparity
 * Collateral: Exogenous
 * Relative Stability: Pegged to USD
 *
 * This is a contract meant to be governed by DSCEngine
 */
contract DecentralizedStablecoin is ERC20Burnable, Ownable {
    error DecentralizedStablecoin__MustBeMoreThanZero();
    error DecentralizedStablecoin__BurnAmountExceedsBalance();
    error DecentralizedStablecoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStablecoin", "DS") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStablecoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStablecoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount); // super says use burn function from parent class (ERC20Burnable)
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStablecoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStablecoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
