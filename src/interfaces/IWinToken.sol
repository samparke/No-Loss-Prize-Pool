// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWinToken {
    function mint(address user, uint256 amount) external;
    function burn(uint256 amount) external;
    function hasMintAndBurnRole(address user) external view returns (bool);
    function balanceOf(address user) external view returns (uint256);
}
