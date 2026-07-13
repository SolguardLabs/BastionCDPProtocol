// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionCDP } from "../src/BastionCDP.sol";
import { MedianPriceOracle } from "../src/oracle/MedianPriceOracle.sol";
import { BastionCollateralToken } from "../src/tokens/BastionCollateralToken.sol";
import { Script } from "forge-std/Script.sol";

contract DeployBastion is Script {
    function run()
        external
        returns (BastionCDP protocol, BastionCollateralToken collateral, MedianPriceOracle oracle)
    {
        vm.startBroadcast();

        address admin = msg.sender;

        protocol = new BastionCDP(admin, 500);
        collateral =
            new BastionCollateralToken(admin, "Bastion Ether", "bETH", 1_000_000e18, 100e18);
        oracle = new MedianPriceOracle(admin);
        oracle.postPrice(address(collateral), 2000e18);

        protocol.configureCollateral(
            address(collateral),
            address(oracle),
            "bETH",
            10_000_000e18,
            500e18,
            15_000,
            1300,
            1 hours,
            500,
            10_000,
            true
        );

        vm.stopBroadcast();
    }
}
