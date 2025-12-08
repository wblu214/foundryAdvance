// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract CreateSubscription is Script {
    function createSubscriptionConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();

        address vrfCoordinator = helperConfig
            .getActiveNetworkConfig()
            .vrfCoordinator;

        // create subscriptionID
        (uint256 subsID, ) = createSubscriptionID(vrfCoordinator);
        return (subsID, vrfCoordinator);
    }

    function createSubscriptionID(
        address vrfCoordinator
    ) public returns (uint256, address) {
        console.log("createSubscriptionID on chain ID: ", block.chainid);
        vm.startBroadcast();
        uint256 subsID = VRFCoordinatorV2_5Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Subscription ID: ", subsID);
        console.log("Please update the HelperConfig with this subscription ID");
        return (subsID, vrfCoordinator);
    }

    function run() public {
        createSubscriptionConfig();
    }
}
