// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract WinToken is ERC20, Ownable, ERC20Burnable {
    error WinToken__MustBeMoreThanZero();
    error WinToken__BalanceMustExceedBurnAmount();

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert WinToken__MustBeMoreThanZero();
        }
        _;
    }

    constructor() ERC20("WinToken", "WIN") Ownable(msg.sender) {}

    function mint(address _user, uint256 _amount) public moreThanZero(_amount) returns (bool) {
        _mint(_user, _amount);
        return true;
    }

    function burn(uint256 _amount) public override moreThanZero(_amount) onlyOwner {
        uint256 userBalance = balanceOf(msg.sender);
        if (userBalance < _amount) {
            revert WinToken__BalanceMustExceedBurnAmount();
        }
        super.burn(_amount);
    }
}
