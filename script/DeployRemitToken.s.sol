// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {RemitToken} from "../src/RemitToken.sol";

contract DeployRemitToken is Script {
    function run() public {
        // Load the deployer's private key from the .env file
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deploying RemitToken with address:", deployerAddress);

        // Begin broadcasting transactions to the network
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract, passing the deployer as the initial owner
        RemitToken token = new RemitToken(deployerAddress);

        vm.stopBroadcast();

        console.log("RemitToken deployed to:", address(token));
    }
}
