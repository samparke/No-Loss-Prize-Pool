// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IWinToken} from "../src/interfaces/IWinToken.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Pool is AccessControl, Ownable {
    // erros
    error Pool__MustSendEth();

    IWinToken private immutable i_winToken;
    // the total deposits for everyone
    uint256 public totalDeposits;
    // the accumulated interest to be won
    uint256 poolBalance;
    // last time the contract accrued interest to balance
    uint256 lastAccrued;
    // this is each users deposits + interest accrued
    mapping(address user => uint256 amountDeposited) private s_amountUserDeposited;
    // this is the list of address of users who have deposited
    address[] private s_participants;
    // this is 0.00000005 per second, equivalent to 5% annually
    uint256 public s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    // scale up to 18 decimals
    uint256 private constant PRECISION_FACTOR = 1e18;
    // this is the role for the chainlink automator to distribute the contracts funds to a lucky address
    bytes32 private constant DISTRIBUTE_INTEREST_ROLE = keccak256("DISTRIBUTE_INTEREST_ROLE");

    // events
    event Deposit(address indexed user, uint256 amount);
    event InterestRateChange(uint256 newInterestRate);

    constructor(IWinToken _i_winToken) Ownable(msg.sender) {
        i_winToken = _i_winToken;
        totalDeposits = 0;
    }

    receive() external payable {}

    /**
     * @notice this function deposits eth into the contract
     */
    function deposit() external payable {
        s_amountUserDeposited[msg.sender] += msg.value;
        totalDeposits += msg.value;
        _accrueInterest();
        if (msg.value == 0) {
            revert Pool__MustSendEth();
        }
        // if user has never deposited, add them to the list of depositers
        if (s_amountUserDeposited[msg.sender] == 0) {
            s_participants.push(msg.sender);
        }

        i_winToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    // interest

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        s_interestRate = _newInterestRate;
    }

    /**
     * @notice this function adds to accumulated interest since the last time this function was called
     * uint256 timeElapsed is the time (in seconds) since the last time interest was accrued to the contract
     * uint256 interestToMint calculates the interest (by mutliplying the total deposits, by interest rate, by the time in seconds)
     * it then mints this to the contract (pool), and sets the lastAccrued (last time interest was added to the pool balance)
     */
    function _accrueInterest() internal {
        uint256 timeElapsed = block.timestamp - lastAccrued;
        if (timeElapsed == 0) {
            return;
        }
        uint256 interestToMint = (totalDeposits * s_interestRate * timeElapsed) / PRECISION_FACTOR;
        poolBalance += interestToMint;
        lastAccrued = block.timestamp;
    }

    // getters

    function getHasUserDeposited(address _user) external view returns (bool) {
        for (uint256 i = 0; i < s_participants.length; i++) {
            if (s_participants[i] == _user) {
                return true;
            }
        }
        return false;
    }

    function getPoolBalance() external view returns (uint256) {
        return poolBalance;
    }
}
