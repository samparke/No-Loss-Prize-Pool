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
        winToken.grantMintAndBurnRole(address(pool));
        vm.deal(user, STARTING_USER_BALANCE);
        vm.deal(address(pool), 1000 ether);
    }

    // deposit

    function testUserDepositsAndGiveUser10WinTokens() public {
        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit Pool.Deposit(address(user), DEPOSIT_AMOUNT);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        assertEq(winToken.balanceOf(user), 1 ether);
    }

    function testUserDeposits1ETHAndPoolBalanceIncreasesAfter30Days() public {
        uint256 initialPoolBalance = pool.getPoolBalance();
        assertEq(initialPoolBalance, 0);
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        vm.warp(block.timestamp + 30 days);
        uint256 futurePoolBalance = pool.getPoolBalance();
        assertGt(futurePoolBalance, initialPoolBalance);
    }

    function testUserDeposits2ETHAndPoolBalanceIsDouble1ETHInterest() public {
        vm.prank(user);
        // considering we are accruing interest linearly, and we are deposited double the previous test (which returned 50000000000 WEI)
        // this should return (50000000000 * 2)
        pool.deposit{value: DEPOSIT_AMOUNT * 2}();
        vm.warp(block.timestamp + 30 days);
        uint256 poolBalance = pool.getPoolBalance();
        // 50000000000 WEI / 0.00000005 ETH > 0 ETH
        assertEq(poolBalance, (50000000000 * 2));
    }

    function testUserDepositsNoEth() public {
        vm.prank(user);
        vm.expectRevert(Pool.Pool__MustSendEth.selector);
        pool.deposit{value: 0}();
    }

    // withdraw

    function testWithdrawStakeStraightAway() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        assertEq(address(user).balance, 9 ether);
        // approve the pool contract to return the win tokens back to win token contract
        winToken.approve(address(pool), winToken.balanceOf(user));
        pool.withdraw(DEPOSIT_AMOUNT);
        assertEq(address(user).balance, 10 ether);
        vm.stopPrank();
    }

    function testWithdrawAndUserNoLongerParticipantStraightAway() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        assertTrue(pool.getIsUserParticipant(user));
        winToken.approve(address(pool), winToken.balanceOf(user));
        pool.withdraw(DEPOSIT_AMOUNT);
        assertFalse(pool.getIsUserParticipant(user));
        vm.stopPrank();
    }

    function testWithdrawAndUserNoLongerParticipantAfterManyDifferentUserDeposits() public {
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);

        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        winToken.approve(address(pool), winToken.balanceOf(user));
        vm.stopPrank();
        assertTrue(pool.getIsUserParticipant(user));

        vm.startPrank(user2);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        winToken.approve(address(pool), winToken.balanceOf(user2));
        vm.stopPrank();
        assertTrue(pool.getIsUserParticipant(user2));

        vm.startPrank(user3);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        winToken.approve(address(pool), winToken.balanceOf(user3));
        vm.stopPrank();
        assertTrue(pool.getIsUserParticipant(user3));

        // the user is no longer first in the index array
        vm.prank(user);
        pool.withdraw(DEPOSIT_AMOUNT);
        assertFalse(pool.getIsUserParticipant(user));
    }

    function testWithdrawIfNotDepositedRevert() public {
        vm.prank(user);
        vm.expectRevert(Pool.Pool__ParticipantIsNotInList.selector);
        pool.withdraw(DEPOSIT_AMOUNT);
    }

    function testUserAttemptsToWithdrawMoreThanDeposited() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        winToken.approve(address(pool), winToken.balanceOf(user));
        vm.expectRevert(Pool.Pool__CanOnlyWithdrawDepositedAmountOrLess.selector);
        pool.withdraw(DEPOSIT_AMOUNT + 1);
        vm.stopPrank();
    }

    function testUserRedeemsAndIsNoLongerInList() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        winToken.approve(address(pool), winToken.balanceOf(user));
        pool.withdraw(DEPOSIT_AMOUNT);
        vm.stopPrank();
        assertFalse(pool.getIsUserParticipant(user));
    }

    function testUserDepositsAndWithdrawsTotalDepositAndHasNoWinTokensLeft() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        uint256 userWinBalance = winToken.balanceOf(user);
        assertEq(userWinBalance, DEPOSIT_AMOUNT);
        winToken.approve(address(pool), winToken.balanceOf(user));
        pool.withdraw(DEPOSIT_AMOUNT);
        uint256 userWinBalanceAfterWithdraw = winToken.balanceOf(user);
        assertEq(userWinBalanceAfterWithdraw, 0);
        vm.stopPrank();
    }

    function testUserDepositsAndWithdrawsHalfDepositAndHasHalfWinTokensLeft() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        uint256 userWinBalance = winToken.balanceOf(user);
        assertEq(userWinBalance, DEPOSIT_AMOUNT);
        winToken.approve(address(pool), winToken.balanceOf(user));
        pool.withdraw(DEPOSIT_AMOUNT / 2);
        uint256 userWinBalanceAfterWithdraw = winToken.balanceOf(user);
        assertEq(userWinBalanceAfterWithdraw, DEPOSIT_AMOUNT / 2);
        vm.stopPrank();
    }

    // random

    function testRandomNumberNotYetFound() public {
        vm.expectRevert(Pool.Pool__NoRandomnessYet.selector);
        pool.selectWinner();
    }
}
