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

    function testUserDepositsAndGiveUser10WinTokens() public {
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        assertEq(winToken.balanceOf(user), 1);
    }

    function testUserDeposits1ETHAndPoolBalanceIncreasesAfter30Days() public {
        uint256 initialPoolBalance = pool.getPoolBalance();
        assertEq(initialPoolBalance, 0);
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}();
        vm.warp(block.timestamp + 30 days);
        uint256 futurePoolBalance = pool.getPoolBalance();
        // 50000000000 WEI / 0.00000005 ETH > 0 ETH
        assertGt(futurePoolBalance, initialPoolBalance);
    }

    function testUserDeposits2ETHAndPoolBalanceIsDouble1ETHInterest() public {
        vm.prank(user);
        // considering we are accruing interest linearly, and we are deposited double the previous test (which returned 50000000000 WEI)
        // this should return (50000000000 * 2)
        pool.deposit{value: 2 ether}();
        vm.warp(block.timestamp + 30 days);
        uint256 poolBalance = pool.getPoolBalance();
        // 50000000000 WEI / 0.00000005 ETH > 0 ETH
        assertEq(poolBalance, (50000000000 * 2));
    }
}
