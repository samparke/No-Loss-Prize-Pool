// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract WinToken is ERC20, AccessControl, Ownable, ERC20Burnable {
    error WinToken__MustBeMoreThanZero();
    error WinToken__BalanceMustExceedBurnAmount();

    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert WinToken__MustBeMoreThanZero();
        }
        _;
    }

    constructor() ERC20("WinToken", "WIN") Ownable(msg.sender) {
        grantMintAndBurnRole(msg.sender);
    }

    function grantMintAndBurnRole(address _user) public onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _user);
    }

    function mint(address _user, uint256 _amount)
        public
        moreThanZero(_amount)
        onlyRole(MINT_AND_BURN_ROLE)
        returns (bool)
    {
        _mint(_user, _amount);
        return true;
    }

    function burn(uint256 _amount) public override moreThanZero(_amount) onlyRole(MINT_AND_BURN_ROLE) {
        uint256 userBalance = balanceOf(msg.sender);
        if (userBalance < _amount) {
            revert WinToken__BalanceMustExceedBurnAmount();
        }
        super.burn(_amount);
    }

    function hasMintAndBurnRole(address _account) public view returns (bool) {
        return hasRole(MINT_AND_BURN_ROLE, _account);
    }
}
