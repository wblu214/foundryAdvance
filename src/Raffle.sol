// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title 抽奖活动
 * @author wblu214
 * @notice this contract is for creating a simple raffle
 */
contract Raffle is VRFConsumerBaseV2Plus {
    // Type declarations
    // State variables
    // Events
    // Modifiers
    // Functions

    error NotEnoughEth();
    error NotSendWinnerMoney();
    error WaitNextDrawTime();

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    address payable[] private s_players;
    //入场费
    uint256 private immutable i_enteranceFee;
    //开奖间隔时间
    uint256 private immutable i_interval;

    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    address payable private s_recentAddress;
    RaffleState private s_raffleState;

    //上次开奖时间
    uint256 private s_lastTimeStamp;

    //事件
    event RaffleEntered(address indexed player);
    event RaffleWinnerPicked(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gsaLine,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_enteranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gsaLine;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    //CEI: Checks, Effects, Interactions Patten
    function getEntranceFee() public view returns (uint256) {
        return i_enteranceFee;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function payEntranceFee() public payable {
        if (msg.value < i_enteranceFee) {
            revert NotEnoughEth();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert WaitNextDrawTime();
        }

        s_players.push(payable(msg.sender));

        emit RaffleEntered(msg.sender);
    }

    function pickWinner() public {
        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert WaitNextDrawTime();
        }

        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentAddress = recentWinner;
        //将抽奖状态重新置为OPEN
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert NotSendWinnerMoney();
        }
        emit RaffleWinnerPicked(recentWinner);
    }
}
