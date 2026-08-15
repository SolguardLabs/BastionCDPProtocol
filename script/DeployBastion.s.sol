// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionCDP } from "../src/BastionCDP.sol";
import { BastionRoles } from "../src/access/BastionAccessControl.sol";
import { CollateralAuctionHouse } from "../src/auctions/CollateralAuctionHouse.sol";
import { DebtAuctionHouse } from "../src/auctions/DebtAuctionHouse.sol";
import { AccountingEngine } from "../src/core/AccountingEngine.sol";
import { RiskEngine } from "../src/core/RiskEngine.sol";
import { StabilityFeeController } from "../src/core/StabilityFeeController.sol";
import { VaultLedger } from "../src/core/VaultLedger.sol";
import { MedianPriceOracle } from "../src/oracle/MedianPriceOracle.sol";
import { BastionCollateralToken } from "../src/tokens/BastionCollateralToken.sol";
import { BastionDebtToken } from "../src/tokens/BastionDebtToken.sol";
import { BastionProtocolShare } from "../src/tokens/BastionProtocolShare.sol";
import { Script } from "forge-std/Script.sol";

contract DeployBastion is Script {
    function run()
        external
        returns (BastionCDP protocol, BastionCollateralToken collateral, MedianPriceOracle oracle)
    {
        vm.startBroadcast();
        address admin = msg.sender;

        BastionDebtToken debt = new BastionDebtToken(admin);
        BastionProtocolShare share = new BastionProtocolShare(admin);
        VaultLedger ledger = new VaultLedger(admin);
        AccountingEngine accounting = new AccountingEngine(admin);
        StabilityFeeController fees = new StabilityFeeController(admin, 500);
        RiskEngine risk = new RiskEngine();
        CollateralAuctionHouse collateralAuction = new CollateralAuctionHouse(admin, debt);
        DebtAuctionHouse debtAuction = new DebtAuctionHouse(admin, debt, share);

        protocol = new BastionCDP(
            admin, debt, share, ledger, accounting, fees, risk, collateralAuction, debtAuction
        );

        debt.grantRole(BastionRoles.TOKEN_MINTER_ROLE, address(protocol));
        debt.grantRole(BastionRoles.TOKEN_BURNER_ROLE, address(protocol));
        debt.grantRole(BastionRoles.TOKEN_BURNER_ROLE, address(collateralAuction));
        debt.grantRole(BastionRoles.TOKEN_BURNER_ROLE, address(debtAuction));
        share.grantRole(BastionRoles.TOKEN_MINTER_ROLE, address(debtAuction));

        ledger.grantRole(BastionRoles.PROTOCOL_ROLE, address(protocol));
        ledger.grantRole(BastionRoles.RISK_MANAGER_ROLE, address(protocol));
        accounting.grantRole(BastionRoles.PROTOCOL_ROLE, address(protocol));
        accounting.grantRole(BastionRoles.AUCTIONEER_ROLE, address(collateralAuction));
        accounting.grantRole(BastionRoles.AUCTIONEER_ROLE, address(debtAuction));
        fees.grantRole(BastionRoles.PROTOCOL_ROLE, address(protocol));
        fees.grantRole(BastionRoles.RISK_MANAGER_ROLE, address(protocol));

        collateralAuction.grantRole(BastionRoles.AUCTIONEER_ROLE, address(protocol));
        collateralAuction.grantRole(BastionRoles.RISK_MANAGER_ROLE, address(protocol));
        collateralAuction.setAccounting(address(accounting));
        debtAuction.grantRole(BastionRoles.AUCTIONEER_ROLE, address(protocol));
        debtAuction.grantRole(BastionRoles.RISK_MANAGER_ROLE, address(protocol));
        debtAuction.setAccounting(address(accounting));

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
