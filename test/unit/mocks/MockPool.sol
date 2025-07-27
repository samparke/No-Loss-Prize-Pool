// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IWinToken} from "../../../src/interfaces/IWinToken.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract MockPool is VRFConsumerBaseV2Plus, AccessControl {
    IWinToken private immutable i_winToken;
    uint256 public s_totalDeposits;
    uint256 public s_poolBalance;
    uint256 public s_lastAccrued;
    mapping(address user => uint256 amountDeposited) private s_amountUserDeposited;
    mapping(address user => bool) private s_isParticipant;
    mapping(address user => uint256 index) private s_indexOfUser;
    address[] private s_participants;
    uint256 public immutable s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant DISTRIBUTE_INTEREST_ROLE = keccak256("DISTRIBUTE_INTEREST_ROLE");

    uint256 immutable s_subscriptionId;
    bytes32 immutable s_keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    uint32 constant CALLBACK_GAS_LIMIT = 100000;
    uint16 constant REQUEST_CONFIRMATIONS = 3;
    uint32 constant NUM_WORDS = 1;

    uint256[] public s_randomWords;
    uint256 public s_requestId;
    address public s_winner;

    event Deposit(address indexed user, uint256 amount);
    event InterestRateChange(uint256 newInterestRate);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event WinnerSelected(address indexed winner);
    event WinnerPaid(address indexed winner, uint256 prize, bool wasSuccessful);
    event ReturnedRandomness(uint256[] randomWords);

    error Pool__MustSendEth();
    error Pool__CanOnlyWithdrawDepositedAmountOrLess();
    error Pool__ParticipantIsNotInList();
    error Pool_WithdrawTransferBackToUserFail();
    error Pool__WinnerNotFound();
    error Pool_WinnerPrizeTransferFailed();
    error Pool__RandomNumberNotFound();
    error Pool__NoRandomnessYet();

    constructor(IWinToken _i_winToken, uint256 subscriptionId, address vrfCoordinator)
        VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        i_winToken = _i_winToken;
        s_totalDeposits = 0;
        s_keyHash = s_keyHash;
        s_subscriptionId = subscriptionId;
    }

    function requestRandomWords() public onlyOwner {
        s_requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
    }

    function fulfillRandomWords(uint256, /* requestId */ uint256[] calldata randomWords) internal override {
        s_randomWords = randomWords;
        emit ReturnedRandomness(randomWords);
    }

    receive() external payable {}

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

    function _accrueInterest() internal {
        uint256 timeElapsed = block.timestamp - s_lastAccrued;
        if (timeElapsed == 0) {
            return;
        }
        uint256 interestToMint = (s_totalDeposits * s_interestRate * timeElapsed) / PRECISION_FACTOR;
        s_poolBalance += interestToMint;
        s_lastAccrued = block.timestamp;
    }

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

    // MUST ASSIGN ROLE
    function selectWinner() public {
        if (s_randomWords.length == 0) {
            revert Pool__NoRandomnessYet();
        }
        uint256 randomWord = getRandomWord();
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

    function getIsUserParticipant(address _user) external view returns (bool) {
        return s_isParticipant[_user];
    }

    function getPoolBalance() external view returns (uint256) {
        return s_poolBalance;
    }

    function getRandomWordsArrayLength() external view returns (uint256) {
        return s_randomWords.length;
    }

    function getRandomWord() public view returns (uint256) {
        return s_randomWords[0];
    }
}
