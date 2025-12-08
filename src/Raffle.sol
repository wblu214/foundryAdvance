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

    error Raffle_CheckUpKeepNotNeed(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );

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
    address payable[] private players;
    // 入场费，不可变变量，部署后不可更改
    uint256 private immutable ENTRANCE_FEE;
    // 开奖间隔时间（秒），不可变变量，部署后不可更改
    uint256 private immutable INTERVAL;

    // Chainlink VRF相关参数
    // VRF密钥哈希，用于标识VRF服务
    bytes32 private immutable KEY_HASH;
    // VRF订阅ID，用于支付VRF服务费用
    uint256 private immutable SUBSCRIPTION_ID;
    // VRF请求确认数，确保随机性的可靠性
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    // 回调函数的Gas限制，防止Gas耗尽
    uint32 private immutable CALLBACK_GAS_LIMIT;
    // 请求的随机数数量
    uint32 private constant NUM_WORDS = 1;
    // 最近一次抽奖的获胜者地址
    address payable private recentWinner;
    // 当前抽奖状态
    RaffleState private raffleState;

    // 上次开奖时间戳
    uint256 private lastTimeStamp;

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
        ENTRANCE_FEE = entranceFee;
        INTERVAL = interval;
        KEY_HASH = gsaLine;
        SUBSCRIPTION_ID = subscriptionId;
        CALLBACK_GAS_LIMIT = callbackGasLimit;

        raffleState = RaffleState.OPEN;
        lastTimeStamp = block.timestamp;
    }

    //CEI: Checks, Effects, Interactions Patten

    /**
     * @dev 获取入场费
     * @return 入场费金额
     */
    function getEntranceFee() public view returns (uint256) {
        return ENTRANCE_FEE;
    }

    /**
     * @dev 获取上次开奖时间戳
     * @return 上次开奖的时间戳
     */
    function getLastTimeStamp() public view returns (uint256) {
        return lastTimeStamp;
    }

    /**
     * @dev 支付入场费参与抽奖
     * @notice 调用者必须发送至少等于入场费的ETH
     * @notice 只有在抽奖状态为OPEN时才能参与
     */
    function payEntranceFee() public payable {
        if (msg.value < ENTRANCE_FEE) {
            revert NotEnoughEth();
        }
        if (raffleState != RaffleState.OPEN) {
            revert WaitNextDrawTime();
        }

        players.push(payable(msg.sender));

        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev 请求随机数并开始抽取获胜者
     * @notice 只有在距离上次开奖时间超过间隔时间时才能调用
     * @notice 将抽奖状态设置为CALCULATING，防止新的参与者加入
     */
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_CheckUpKeepNotNeed(
                address(this).balance,
                players.length,
                uint256(raffleState)
            );
        }

        raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: KEY_HASH,
                subId: SUBSCRIPTION_ID,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        s_vrfCoordinator.requestRandomWords(request);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = block.timestamp - lastTimeStamp >= INTERVAL;
        bool hasPlayers = players.length > 0;
        bool isOpen = raffleState == RaffleState.OPEN;
        upkeepNeeded = (timeHasPassed && hasPlayers && isOpen);
        return (upkeepNeeded, "");
    }

    /**
     * @dev Chainlink VRF回调函数，处理随机数并选出获胜者
     * @param randomWords VRF返回的随机数数组
     * @notice 使用随机数模玩家数量来选择获胜者
     * @notice 将奖池中的所有ETH发送给获胜者
     * @notice 重置抽奖状态，清空玩家列表，更新开奖时间
     */
    function fulfillRandomWords(
        uint256 /*_requestId*/,
        uint256[] calldata randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % players.length;
        address payable winner = players[indexOfWinner];
        recentWinner = winner;
        //将抽奖状态重新置为OPEN
        raffleState = RaffleState.OPEN;
        players = new address payable[](0);
        lastTimeStamp = block.timestamp;
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert NotSendWinnerMoney();
        }
        emit RaffleWinnerPicked(winner);
    }
}
