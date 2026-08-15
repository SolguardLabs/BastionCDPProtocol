// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { RiskParameterTimelock } from "../src/governance/RiskParameterTimelock.sol";
import { PortfolioRiskEngine } from "../src/risk/PortfolioRiskEngine.sol";
import { BastionVersion } from "../src/version/BastionVersion.sol";
import { Script } from "forge-std/Script.sol";

contract DeployControlPlane is Script {
    function run()
        external
        returns (
            PortfolioRiskEngine portfolioRisk,
            RiskParameterTimelock timelock,
            BastionVersion version
        )
    {
        address admin = msg.sender;
        uint64 minimumDelay = uint64(vm.envOr("BASTION_MINIMUM_DELAY", uint256(2 days)));
        uint64 gracePeriod = uint64(vm.envOr("BASTION_GRACE_PERIOD", uint256(7 days)));

        vm.startBroadcast();
        portfolioRisk = new PortfolioRiskEngine();
        timelock = new RiskParameterTimelock(admin, minimumDelay, gracePeriod);
        version = new BastionVersion();
        vm.stopBroadcast();
    }
}
