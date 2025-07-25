// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IWinToken} from "../src/interfaces/IWinToken.sol";

contract Pool {
    error Pool__MustSendEth();

    IWinToken private immutable i_winToken;
    mapping(address user => uint256 amountDeposited) private s_amountUserDeposited;

    event Deposit(address user, uint256 amount);

    constructor(IWinToken _i_winToken) {
        i_winToken = _i_winToken;
    }

    receive() external payable {}

    function deposit() external payable {
        if (msg.value == 0) {
            revert Pool__MustSendEth();
        }
        s_amountUserDeposited[msg.sender] += msg.value;
        i_winToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }
}
