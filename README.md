## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Raffle 调用流程（整体逻辑）

```
[Player]
  └─ payEntranceFee()               // 发送 >= entranceFee 的 ETH，状态需为 OPEN
      └─ players.push(msg.sender)
      └─ emit RaffleEntered

[Chainlink Automation / keeper]
  └─ checkUpkeep()
        timeHasPassed = now - lastTimeStamp >= interval
        hasPlayers = players.length > 0
        isOpen = raffleState == OPEN
        upkeepNeeded = timeHasPassed && hasPlayers && isOpen

  └─ performUpkeep()                // 仅在 upkeepNeeded 时
        raffleState = CALCULATING
        requestRandomWords(...) -> VRF Coordinator

[VRF Coordinator 回调]
  └─ fulfillRandomWords()
        winner = players[random % players.length]
        raffleState = OPEN; players 清空; lastTimeStamp = now
        发送奖池余额给 winner
        emit RaffleWinnerPicked
```

### 在 Sepolia 部署 Raffle

前置条件：
- 在 `script/HelperConfig.s.sol` 的 `getSepoliaEthConfig` 中填好你的 VRF subscriptionId（已创建且已用 LINK 充值）。
- 环境变量：`SEPOLIA_RPC_URL`、`PRIVATE_KEY`（部署账户），如需验证再加 `ETHERSCAN_API_KEY`。
- 账户中有足够 ETH 支付 gas，subscription 中有 LINK。

部署命令示例：
```shell
forge script script/DeployRaffle.s.sol:DeployRaffle \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify --etherscan-api-key $ETHERSCAN_API_KEY   # 如不验证可去掉
```
脚本会：
1) 使用 HelperConfig 读取 Sepolia 配置；若 subscriptionId 为 0 会尝试创建并充值（Sepolia 分支当前需要你预先提供有效的 subscriptionId）。
2) 部署 Raffle 合约。
3) 将 Raffle 添加为 VRF 订阅的 consumer。

部署后可用 `cast call` 或前端调用 `payEntranceFee()` 参与抽奖，Automation 定时触发 `performUpkeep`，VRF 回调开奖。

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
