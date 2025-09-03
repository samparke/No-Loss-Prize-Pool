// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IWinToken} from "../src/interfaces/IWinToken.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {VRFConsumerBaseV2Plus} from "chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Pool is AccessControl, VRFConsumerBaseV2Plus {
    IWinToken private immutable i_winToken;
    // the total deposits for everyone
    uint256 public s_totalDeposits;
    // the accumulated interest to be won
    uint256 public s_poolBalance;
    // last time the contract accrued interest to balance
    uint256 public s_lastAccrued;
    // this is each users deposits + interest accrued
    mapping(address user => uint256 amountDeposited) private s_amountUserDeposited;
    // bool to whether user is in the participant list
    mapping(address user => bool) private s_isParticipant;
    // the index of the user in the list
    mapping(address user => uint256 index) private s_indexOfUser;
    // this is the list of address of users who have deposited
    address[] private s_participants;
    // this is 0.00000005 per second, equivalent to 5% annually
    uint256 public immutable s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    // scale up to 18 decimals
    uint256 private constant PRECISION_FACTOR = 1e18;
    // this is the role for the chainlink automator to distribute the contracts funds to a lucky address
    bytes32 private constant DISTRIBUTE_INTEREST_ROLE = keccak256("DISTRIBUTE_INTEREST_ROLE");

    //chainlink state variables
    mapping(uint256 => RequestStatus) public s_requests;
    uint256 s_subscriptionId = 20151455610035699335285754041510596714833706118432820466165758446716046642275;
    uint256[] public requestIds;
    uint256 public lastRequestId;
    bytes32 public keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;
    address public s_winner;

    //structs

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }

    // events
    event Deposit(address indexed user, uint256 amount);
    event InterestRateChange(uint256 newInterestRate);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event WinnerSelected(address indexed winner);
    event WinnerPaid(address indexed winner, uint256 prize, bool wasSuccessful);

    // errors
    error Pool__MustSendEth();
    error Pool__CanOnlyWithdrawDepositedAmountOrLess();
    error Pool__ParticipantIsNotInList();
    error Pool_WithdrawTransferBackToUserFail();
    error Pool__WinnerNotFound();
    error Pool_WinnerPrizeTransferFailed();
    error Pool__NoRandomnessYet();

    constructor(IWinToken _i_winToken) VRFConsumerBaseV2Plus(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B) {
        i_winToken = _i_winToken;
        s_totalDeposits = 0;
        s_subscriptionId = s_subscriptionId;
    }

    // chainlink functions

    /**
     * @notice our call to get a random number
     */
    function requestRandomWords() external onlyOwner returns (uint256 requestId) {
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
        s_requests[requestId] = RequestStatus({randomWords: new uint256[](0), exists: true, fulfilled: false});
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    /**
     * @notice this is the function for chainlink vrf to pass the random number through. It additionally calls our internal
     * _select winner function
     * @param _requestId the request Id for the random number to be assigned to
     * @param _randomWords the random word (number) the chainlink vrf inputs
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(_requestId, _randomWords);
    }

    receive() external payable {}

    /**
     * @notice this function deposits eth into the contract
     */
    function deposit() external payable {
        if (msg.value == 0) {
            revert Pool__MustSendEth();
        }
        _addParticipants(msg.sender);
        s_amountUserDeposited[msg.sender] += msg.value;
        s_totalDeposits += msg.value;
        _accrueInterest();

        i_winToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice this function enables users to withdraw the eth they deposited, and return the win tokens, removing them from the pool
     * @param ethToWithdraw the amount of eth to withdraw from the users deposited amount. The amount of win tokens transfered back depends on the withdraw amount
     */
    function withdraw(uint256 ethToWithdraw) external {
        if (!s_isParticipant[msg.sender]) {
            revert Pool__ParticipantIsNotInList();
        }
        if (ethToWithdraw > s_amountUserDeposited[msg.sender]) {
            revert Pool__CanOnlyWithdrawDepositedAmountOrLess();
        }
        if (ethToWithdraw == s_amountUserDeposited[msg.sender]) {
            _removeParticipant(msg.sender);
            i_winToken.returnAllUserTokens(msg.sender);
        }
        s_amountUserDeposited[msg.sender] -= ethToWithdraw;
        s_totalDeposits -= ethToWithdraw;
        i_winToken.returnUserTokens(msg.sender, ethToWithdraw);
        (bool success,) = payable(msg.sender).call{value: ethToWithdraw}("");
        if (!success) {
            revert Pool_WithdrawTransferBackToUserFail();
        }
    }

    // internal functions

    /**
     * @notice selects the winner from our entrants
     * @dev users who deposit more recieve more WIN tokens. We need to give these users a greater chance of winning.
     * the randomTicket selects a random ticket point from the total tickets
     * we add each users balance to cumulative tickets amount, and then test whether the users tickets (at the point of adding to the cumumlativeTicketAmount)
     * is above that random ticket point. If so, they win.
     */
    function selectWinner() public onlyOwner {
        if (!s_requests[lastRequestId].fulfilled) {
            revert Pool__NoRandomnessYet();
        }
        (, uint256[] memory randomWords) = getRequestStatus(lastRequestId);
        uint256 randomWord = randomWords[randomWords.length - 1];
        uint256 totalTickets = i_winToken.totalSupply();
        uint256 randomTicket = randomWord % totalTickets;
        uint256 cumulativeTicketAmount = 0;
        for (uint256 i = 0; i < s_participants.length; i++) {
            address user = s_participants[i];
            uint256 tickets = (i_winToken.balanceOf(s_participants[i]));
            cumulativeTicketAmount += tickets;
            if (randomTicket < cumulativeTicketAmount) {
                s_winner = user;
                break;
            }
        }
        if (s_winner == address(0)) {
            revert Pool__WinnerNotFound();
        }
        emit WinnerSelected(s_winner);
        _payWinnerPrize(s_winner);
    }

    /**
     * @notice this function pays the winner the eth from the pool balance
     * @param _winner the winner address to pay the prize to
     */
    function _payWinnerPrize(address _winner) internal {
        delete s_winner;
        uint256 prize = s_poolBalance;
        s_poolBalance = 0;
        (bool success,) = payable(_winner).call{value: prize}("");
        if (!success) {
            revert Pool_WinnerPrizeTransferFailed();
        }
        emit WinnerPaid(_winner, prize, success);
    }

    /**
     * @notice this function adds to accumulated interest since the last time this function was called
     * uint256 timeElapsed is the time (in seconds) since the last time interest was accrued to the contract
     * uint256 interestToMint calculates the interest (by mutliplying the total deposits, by interest rate, by the time in seconds)
     * it then mints this to the contract (pool), and sets the lastAccrued (last time interest was added to the pool balance)
     */
    function _accrueInterest() internal {
        uint256 timeElapsed = block.timestamp - s_lastAccrued;
        if (timeElapsed == 0) {
            return;
        }
        uint256 interestToMint = (s_totalDeposits * s_interestRate * timeElapsed) / PRECISION_FACTOR;
        s_poolBalance += interestToMint;
        s_lastAccrued = block.timestamp;
    }

    /**
     * @notice this is an internal function to push the user to the list, assigning them an index and true bool
     * @param _user the user we are adding to the list
     */
    function _addParticipants(address _user) internal {
        if (!s_isParticipant[_user]) {
            s_indexOfUser[_user] = s_participants.length;
            s_participants.push(_user);
            s_isParticipant[_user] = true;
        }
    }

    function _removeParticipant(address _user) internal {
        uint256 index = s_indexOfUser[_user];
        uint256 lastIndexInList = s_participants.length - 1;

        if (index != lastIndexInList) {
            address lastUser = s_participants[lastIndexInList];
            s_participants[index] = lastUser;
            s_indexOfUser[lastUser] = index;
        }
        s_participants.pop();

        delete s_indexOfUser[_user];
        s_isParticipant[_user] = false;
    }

    // getters

    function getRequestStatus(uint256 _requestId) public view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }

    /**
     * @notice gets whether the user has deposited (if they are in the deposited list)
     * @param _user the user we want to see if they've deposited
     */
    function getIsUserParticipant(address _user) external view returns (bool) {
        return s_isParticipant[_user];
    }

    /**
     * @return returns the pools balance from interest
     * As the pool will contain ETH outside of the ETH gained from interest accrued, we are tracking balances via
     * uint256 poolBalance, instead of address(this).balance
     */
    function getPoolBalance() external view returns (uint256) {
        return s_poolBalance;
    }
}
