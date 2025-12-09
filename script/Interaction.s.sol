// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/LinkToken.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

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

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig
            .getActiveNetworkConfig()
            .vrfCoordinator;
        uint256 subsID = helperConfig.getActiveNetworkConfig().subscriptionId;

        address linkToken = helperConfig.getActiveNetworkConfig().link;

        fundSubscription(vrfCoordinator, subsID, linkToken);
    }

    function fundSubscription(
        address vrfCoordinatorV2_5,
        uint256 subsID,
        address linkToken
    ) public {
        console.log("fundSubscription on chain ID: ", block.chainid);
        console.log("vrfCoordinator: ", vrfCoordinatorV2_5);
        console.log("subsID: ", subsID);

        if (block.chainid == 31337) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fundSubscription(
                subsID,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            console.log("Fund Subscription :", subsID);
            console.log("Using vrfCoordinator: ", vrfCoordinatorV2_5);
            console.log("On ChainID: ", block.chainid);
            vm.startBroadcast();
            LinkToken(linkToken).transferAndCall(
                vrfCoordinatorV2_5,
                FUND_AMOUNT,
                abi.encode(subsID)
            );
            vm.stopBroadcast();
        }
    }

    function run() public {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function getConsumerConfig(address mostrecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subsId = helperConfig.getActiveNetworkConfig().subscriptionId;
        address vrfCoordinator = helperConfig
            .getActiveNetworkConfig()
            .vrfCoordinator;
        addConsumer(mostrecentlyDeployed, vrfCoordinator, subsId);
    }

    function addConsumer(
        address raffle,
        address contractToAddToVrf,
        uint256 subsId
    ) public {
        console.log("Adding consumer contract: ", contractToAddToVrf);
        console.log("On ChainID: ", block.chainid);
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock(contractToAddToVrf).addConsumer(
            subsId,
            contractToAddToVrf
        );
        vm.stopBroadcast();
    }

    function run() public {
        address mostrecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        getConsumerConfig(mostrecentlyDeployed);
    }
}
