// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedTransfer is ERC20Burnable, Ownable {
    error DecentralizedStablecoin__AmountMustBeMoreThanZero();
    error DecentralizedStablecoin__BurnAmountExceedsBalance();
    error DecentralizedStablecoin__NotZeroAddress();

    constructor() ERC20("Decentralized Stablecoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStablecoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStablecoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function transfer(
        address,
        /*recipient*/
        uint256 /*amount*/
    ) public pure override returns (bool) {
        return false;
    }
}