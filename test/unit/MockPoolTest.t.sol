// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VRFCoordinatorV2_5Mock} from "./mocks/VRFCoordinatorV2_5Mock.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {WinToken} from "../../src/WinToken.sol";
import {IWinToken} from "../../src/interfaces/IWinToken.sol";

contract MockPoolTest is Test {
    VRFCoordinatorV2_5Mock vrfMock;
    MockPool pool;
    WinToken token;
    uint96 baseFee = 100000000000000000;
    uint96 gasPrice = 1000000000;
    int256 weiPerUnitLink = 4923000000000000;

    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    uint256 public constant DEPOSIT_AMOUNT = 1 ether;
    uint256 STARTING_USER_BALANCE = 10 ether;

    function setUp() public {
        vrfMock = new VRFCoordinatorV2_5Mock(baseFee, gasPrice, weiPerUnitLink);
        uint256 subsciption = vrfMock.createSubscription();
        vrfMock.fundSubscription(subsciption, 100000000000000000000);
        token = new WinToken();
        pool = new MockPool(IWinToken(address(token)), subsciption, address(vrfMock));
        vrfMock.addConsumer(subsciption, address(pool));

        token.grantMintAndBurnRole(address(pool));
        vm.deal(user, STARTING_USER_BALANCE);
        vm.deal(user2, STARTING_USER_BALANCE);
        vm.deal(user3, STARTING_USER_BALANCE);
        vm.deal(address(pool), 1000 ether);
    }

    function testRandomWordsAndSelectWinnerFromOneEntrant() public {
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        pool.requestRandomWords();
        uint256 requestId = pool.s_requestId();
        assertEq(requestId, 1);
        vm.expectEmit(true, false, false, false);
        emit MockPool.WinnerSelected(address(user));
        vrfMock.fulfillRandomWords(requestId, address(pool));

        // we requested 1 number of words
        assertEq(pool.getRandomWordsArrayLength(), 1);
        uint256 randomWord = pool.s_randomWords(0);
        assertGt(randomWord, 0);
    }

    // the test alwyas returns the same random number (78541660797044910968829902406342334108369226379826116161446442989268089806461)
    // and when modulo, it alwyas returns 1442989268089806461 - which falls on user 2 every time
    function testRandomWordsAndSelectWinnerOutOfManyEntrantsOfEqualDeposits() public {
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        vm.prank(user2);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        vm.prank(user3);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        pool.requestRandomWords();
        uint256 requestId = pool.s_requestId();
        assertEq(requestId, 1);
        vrfMock.fulfillRandomWords(requestId, address(pool));
        vm.expectEmit(true, false, false, false);
        emit MockPool.WinnerSelected(address(user2));
        pool.selectWinner();
        // console.log("modelo random word", pool.s_randomWords(0) % token.totalSupply());

        // we requested 1 number of words
        assertEq(pool.getRandomWordsArrayLength(), 1);
        uint256 randomWord = pool.s_randomWords(0);
        assertGt(randomWord, 0);
    }

    function testRandomWordsAndSelectWinnerOutOfManyEntrantsOfRandomDeposits(uint256 depositAmount) public {
        // users depositing different amounts
        uint256 depositAmount1 = bound(depositAmount, 1e5, 1e20);
        // uint256 depositAmount2 = bound(depositAmount, 1e5, 1e20);
        // uint256 depositAmount3 = bound(depositAmount, 1e5, 1e20);
        vm.deal(user, depositAmount1);
        // vm.deal(user2, depositAmount2);
        // vm.deal(user3, depositAmount3);
        vm.prank(user);
        pool.deposit{value: depositAmount1}();
        // vm.prank(user2);
        // pool.deposit{value: depositAmount2}();
        // vm.prank(user3);
        // pool.deposit{value: depositAmount3}();

        pool.requestRandomWords();
        uint256 requestId = pool.s_requestId();
        assertEq(requestId, 1);
        vrfMock.fulfillRandomWords(requestId, address(pool));
        // console.log("modelo random word", pool.s_randomWords(0) % token.totalSupply());

        // we requested 1 number of words
        assertEq(pool.getRandomWordsArrayLength(), 1);
        uint256 randomWord = pool.s_randomWords(0);
        assertGt(randomWord, 0);
    }

    function testUserDepositsAndGiveUser10tokens() public {
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        assertEq(token.balanceOf(user), 1 ether);
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

    // withdraw

    function testWithdrawStakeStraightAway() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        assertEq(address(user).balance, 9 ether);
        // approve the pool contract to return the win tokens back to win token contract
        token.approve(address(pool), token.balanceOf(user));
        pool.withdraw(DEPOSIT_AMOUNT);
        assertEq(address(user).balance, 10 ether);
        vm.stopPrank();
    }

    function testWithdrawAndUserNoLongerParticipantStraightAway() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        assertTrue(pool.getIsUserParticipant(user));
        token.approve(address(pool), token.balanceOf(user));
        pool.withdraw(DEPOSIT_AMOUNT);
        assertFalse(pool.getIsUserParticipant(user));
        vm.stopPrank();
    }

    function testWithdrawAndUserNoLongerParticipantAfterManyDifferentUserDeposits() public {
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);

        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        token.approve(address(pool), token.balanceOf(user));
        vm.stopPrank();
        assertTrue(pool.getIsUserParticipant(user));

        vm.startPrank(user2);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        token.approve(address(pool), token.balanceOf(user2));
        vm.stopPrank();
        assertTrue(pool.getIsUserParticipant(user2));

        vm.startPrank(user3);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        token.approve(address(pool), token.balanceOf(user3));
        vm.stopPrank();
        assertTrue(pool.getIsUserParticipant(user3));

        // the user is no longer first in the index array
        vm.prank(user);
        pool.withdraw(DEPOSIT_AMOUNT);
        assertFalse(pool.getIsUserParticipant(user));
    }

    function testWithdrawIfNotDepositedRevert() public {
        vm.prank(user);
        vm.expectRevert(MockPool.Pool__ParticipantIsNotInList.selector);
        pool.withdraw(DEPOSIT_AMOUNT);
    }

    function testUserAttemptsToWithdrawMoreThanDeposited() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        token.approve(address(pool), token.balanceOf(user));
        vm.expectRevert(MockPool.Pool__CanOnlyWithdrawDepositedAmountOrLess.selector);
        pool.withdraw(DEPOSIT_AMOUNT + 1);
        vm.stopPrank();
    }

    function testUserDepositsAndWithdrawsTotalDepositAndHasNotokensLeft() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        uint256 userWinBalance = token.balanceOf(user);
        assertEq(userWinBalance, DEPOSIT_AMOUNT);
        token.approve(address(pool), token.balanceOf(user));
        pool.withdraw(DEPOSIT_AMOUNT);
        uint256 userWinBalanceAfterWithdraw = token.balanceOf(user);
        assertEq(userWinBalanceAfterWithdraw, 0);
        vm.stopPrank();
    }

    function testUserDepositsAndWithdrawsHalfDepositAndHasHalftokensLeft() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        uint256 userWinBalance = token.balanceOf(user);
        assertEq(userWinBalance, DEPOSIT_AMOUNT);
        token.approve(address(pool), token.balanceOf(user));
        pool.withdraw(DEPOSIT_AMOUNT / 2);
        uint256 userWinBalanceAfterWithdraw = token.balanceOf(user);
        assertEq(userWinBalanceAfterWithdraw, DEPOSIT_AMOUNT / 2);
        vm.stopPrank();
    }
}
