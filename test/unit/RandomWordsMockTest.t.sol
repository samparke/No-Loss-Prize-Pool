// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VRFCoordinatorV2_5Mock} from "./mocks/VRFCoordinatorV2_5Mock.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {WinToken} from "../../src/WinToken.sol";
import {IWinToken} from "../../src/interfaces/IWinToken.sol";

contract RandomWordsMockTest is Test {
    VRFCoordinatorV2_5Mock vrfMock;
    MockPool pool;
    WinToken token;
    uint96 baseFee = 100000000000000000;
    uint96 gasPrice = 1000000000;
    int256 weiPerUnitLink = 4923000000000000;

    function setUp() public {
        vrfMock = new VRFCoordinatorV2_5Mock(baseFee, gasPrice, weiPerUnitLink);
        uint256 subsciption = vrfMock.createSubscription();
        vrfMock.fundSubscription(subsciption, 100000000000000000000);
        token = new WinToken();
        pool = new MockPool(IWinToken(address(token)), subsciption, address(vrfMock));
        vrfMock.addConsumer(subsciption, address(pool));
    }

    function testRequestRandomWords() public {
        pool.requestRandomWords();
        uint256 requestId = pool.s_requestId();
        assertEq(requestId, 1);
        vrfMock.fulfillRandomWords(requestId, address(pool));

        // we requested 1 number of words
        assertEq(pool.getRandomWordsArrayLength(), 1);
        uint256 randomWord = pool.s_randomWords(0);
        assertGt(randomWord, 0);
    }
}
