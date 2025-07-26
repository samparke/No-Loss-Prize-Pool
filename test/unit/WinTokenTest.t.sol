// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {WinToken} from "../../src/WinToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract WinTokenTest is Test {
    WinToken winToken;
    address user = makeAddr("user");
    uint256 private constant ETH_TO_WIN_SCALE = 1e17;

    function setUp() public {
        winToken = new WinToken();
    }

    function testIfWinTokenDeployerHasMintAndBurnRoleStraightAway() public view {
        assertTrue(winToken.hasMintAndBurnRole(address(this)));
    }

    function testMintMustbeMoreThanZeroRevert() public {
        vm.expectRevert(WinToken.WinToken__MustBeMoreThanZero.selector);
        winToken.mint(user, 0);
    }

    function testUserMints1EthAndReceives1Win() public {
        winToken.mint(user, 1 ether);
        assertEq(winToken.balanceOf(user), 1);
    }

    function testUserDoesNotHaveMintRole() public {
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        vm.prank(user);
        winToken.mint(user, 1 ether);
    }

    // burn

    function testBurnMoreThanZeroRevert() public {
        vm.expectRevert(WinToken.WinToken__MustBeMoreThanZero.selector);
        winToken.burn(0);
    }

    function testBurnMoreThanBalanceRevert() public {
        vm.expectRevert(WinToken.WinToken__BalanceMustExceedBurnAmount.selector);
        winToken.burn(1 ether);
    }

    // return tokens

    function testReturnAllUserTokensIfUserHasNoneRevert() public {
        vm.expectRevert(WinToken.WinToken__UserHasNoWinTokens.selector);
        winToken.returnAllUserTokens(user);
    }

    function testReturnUserTokensIfUserHasNoneRevert() public {
        vm.expectRevert(WinToken.WinToken__UserHasNoWinTokens.selector);
        winToken.returnUserTokens(user, 1);
    }
}
