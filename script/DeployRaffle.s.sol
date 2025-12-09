// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "../script/Interaction.s.sol";

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig
            .getActiveNetworkConfig();

        if (config.subscriptionId == 0) {
            CreateSubscription subscription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) = subscription
                .createSubscriptionID(config.vrfCoordinator);

            // fund it
            FundSubscription subscriptionFunder = new FundSubscription();
            subscriptionFunder.fundSubscription(
                config.vrfCoordinator,
                config.subscriptionId,
                config.link
            );
        }

        vm.startBroadcast();
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLine,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        // add a consumer
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(raffle),
            config.vrfCoordinator,
            config.subscriptionId
        );

        return (raffle, helperConfig);
    }
}
