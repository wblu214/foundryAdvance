// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title 抽奖活动
 * @author wblu214
 * @notice this contract is for creating a simple raffle
 * @dev 实现了一个基于Chainlink VRF的抽奖合约，参与者支付入场费后进入奖池，
 *      在指定时间间隔后，合约会请求随机数并选出获胜者，将奖池中的所有ETH发送给获胜者。
 */
contract Raffle is VRFConsumerBaseV2Plus {
    // Type declarations
    // State variables
    // Events
    // Modifiers
    // Functions

    // 自定义错误：当支付的ETH不足时触发
    error NotEnoughEth();
    // 自定义错误：当无法将奖金发送给获胜者时触发
    error NotSendWinnerMoney();
    // 自定义错误：当尝试在开奖间隔时间未到时抽取获胜者时触发
    error WaitNextDrawTime();

    /**
     * @dev 抽奖状态枚举
     * OPEN - 抽奖开放，参与者可以支付入场费
     * CALCULATING - 正在计算获胜者，不允许新的参与者加入
     */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // 存储所有参与抽奖的玩家地址
    address payable[] private s_players;
    // 入场费，不可变变量，部署后不可更改
    uint256 private immutable i_enteranceFee;
    // 开奖间隔时间（秒），不可变变量，部署后不可更改
    uint256 private immutable i_interval;

    // Chainlink VRF相关参数
    // VRF密钥哈希，用于标识VRF服务
    bytes32 private immutable i_keyHash;
    // VRF订阅ID，用于支付VRF服务费用
    uint256 private immutable i_subscriptionId;
    // VRF请求确认数，确保随机性的可靠性
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    // 回调函数的Gas限制，防止Gas耗尽
    uint32 private immutable i_callbackGasLimit;
    // 请求的随机数数量
    uint32 private constant NUM_WORDS = 1;
    // 最近一次抽奖的获胜者地址
    address payable private s_recentAddress;
    // 当前抽奖状态
    RaffleState private s_raffleState;

    // 上次开奖时间戳
    uint256 private s_lastTimeStamp;

    // 事件：当有玩家参与抽奖时触发
    event RaffleEntered(address indexed player);
    // 事件：当选出获胜者时触发
    event RaffleWinnerPicked(address indexed winner);

    /**
     * @dev 构造函数，初始化抽奖合约
     * @param entranceFee 参与抽奖所需的入场费
     * @param interval 两次开奖之间的时间间隔（秒）
     * @param vrfCoordinator Chainlink VRF协调器合约地址
     * @param gsaLine VRF密钥哈希
     * @param subscriptionId VRF订阅ID
     * @param callbackGasLimit 回调函数的Gas限制
     */
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

    /**
     * @dev 获取入场费
     * @return 入场费金额
     */
    function getEntranceFee() public view returns (uint256) {
        return i_enteranceFee;
    }

    /**
     * @dev 获取上次开奖时间戳
     * @return 上次开奖的时间戳
     */
    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    /**
     * @dev 支付入场费参与抽奖
     * @notice 调用者必须发送至少等于入场费的ETH
     * @notice 只有在抽奖状态为OPEN时才能参与
     */
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

    /**
     * @dev 请求随机数并开始抽取获胜者
     * @notice 只有在距离上次开奖时间超过间隔时间时才能调用
     * @notice 将抽奖状态设置为CALCULATING，防止新的参与者加入
     */
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

    /**
     * @dev Chainlink VRF回调函数，处理随机数并选出获胜者
     * @param _requestId VRF请求ID
     * @param randomWords VRF返回的随机数数组
     * @notice 使用随机数模玩家数量来选择获胜者
     * @notice 将奖池中的所有ETH发送给获胜者
     * @notice 重置抽奖状态，清空玩家列表，更新开奖时间
     */
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
