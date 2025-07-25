// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {WinToken} from "../../src/WinToken.sol";

contract WinTokenTest is Test {
    WinToken winToken;

    function setUp() public {
        winToken = new WinToken();
    }

    function testIfWinTokenDeployerHasMintAndBurnRoleStraightAway() public view {
        assertTrue(winToken.hasMintAndBurnRole(address(this)));
    }
}
