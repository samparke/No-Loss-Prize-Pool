// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../../src/Pool.sol";
import {WinToken} from "../../src/WinToken.sol";
import {IWinToken} from "../../src/interfaces/IWinToken.sol";

contract PoolTest is Test {
    WinToken winToken;
    address user = makeAddr("user");
    Pool pool;
    uint256 public constant DEPOSIT_AMOUNT = 1 ether;
    uint256 STARTING_USER_BALANCE = 10 ether;

    function setUp() public {
        winToken = new WinToken();
        pool = new Pool(IWinToken(address(winToken)));
        winToken.grantMintAndBurnRole(address(address(pool)));
        vm.deal(user, STARTING_USER_BALANCE);
    }

    function testDepositEventEmittedAndMintUserWinToken() public {
        vm.prank(user);
        vm.expectEmit(true, false, false, true, address(pool));
        emit Pool.Deposit(user, DEPOSIT_AMOUNT);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        assertEq(winToken.balanceOf(user), DEPOSIT_AMOUNT);
        assertTrue(pool.getHasUserDeposited(user));
    }
}
