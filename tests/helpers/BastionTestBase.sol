// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionCDP } from "../../src/BastionCDP.sol";
import { BastionRoles } from "../../src/access/BastionAccessControl.sol";
import { CollateralAuctionHouse } from "../../src/auctions/CollateralAuctionHouse.sol";
import { DebtAuctionHouse } from "../../src/auctions/DebtAuctionHouse.sol";
import { AccountingEngine } from "../../src/core/AccountingEngine.sol";
import { RiskEngine } from "../../src/core/RiskEngine.sol";
import { StabilityFeeController } from "../../src/core/StabilityFeeController.sol";
import { VaultLedger } from "../../src/core/VaultLedger.sol";
import { MedianPriceOracle } from "../../src/oracle/MedianPriceOracle.sol";
import { BastionCollateralToken } from "../../src/tokens/BastionCollateralToken.sol";
import { BastionDebtToken } from "../../src/tokens/BastionDebtToken.sol";
import { BastionProtocolShare } from "../../src/tokens/BastionProtocolShare.sol";
import { BastionTypes } from "../../src/types/BastionTypes.sol";
import { Test } from "forge-std/Test.sol";

contract BastionTestBase is Test {
    address internal admin = address(0xA11CE);
    address internal alice = address(0xB0B01);
    address internal bob = address(0xB0B02);
    address internal keeper = address(0xC0FFEE);

    BastionCDP internal protocol;
    BastionCollateralToken internal collateral;
    MedianPriceOracle internal oracle;
    BastionDebtToken internal debt;
    BastionProtocolShare internal share;
    CollateralAuctionHouse internal collateralAuction;
    DebtAuctionHouse internal debtAuction;

    uint256 internal constant INITIAL_PRICE = 2000e18;
    uint256 internal constant MIN_DEBT = 500e18;
    uint256 internal constant DEBT_CEILING = 10_000_000e18;

    function setUp() public virtual {
        vm.startPrank(admin);

        debt = new BastionDebtToken(admin);
        share = new BastionProtocolShare(admin);
        VaultLedger vaultLedger = new VaultLedger(admin);
        AccountingEngine accountingEngine = new AccountingEngine(admin);
        StabilityFeeController feeController = new StabilityFeeController(admin, 500);
        RiskEngine riskEngine = new RiskEngine();
        collateralAuction = new CollateralAuctionHouse(admin, debt);
        debtAuction = new DebtAuctionHouse(admin, debt, share);
        protocol = new BastionCDP(
            admin,
            debt,
            share,
            vaultLedger,
            accountingEngine,
            feeController,
            riskEngine,
            collateralAuction,
            debtAuction
        );
        _configureModules(vaultLedger, accountingEngine, feeController);

        collateral = new BastionCollateralToken(admin, "Bastion Ether", "bETH", 0, 100e18);
        oracle = new MedianPriceOracle(admin);
        oracle.postPrice(address(collateral), INITIAL_PRICE);

        protocol.configureCollateral(
            address(collateral),
            address(oracle),
            "bETH",
            DEBT_CEILING,
            MIN_DEBT,
            15_000,
            1300,
            1 days,
            500,
            10_000,
            true
        );

        protocol.setCollateralAuctionDuration(1 hours);
        protocol.setDebtAuctionParameters(1 hours, 300);

        collateral.mint(alice, 1000e18);
        collateral.mint(bob, 1000e18);

        vm.stopPrank();
    }

    function _configureModules(
        VaultLedger vaultLedger,
        AccountingEngine accountingEngine,
        StabilityFeeController feeController
    ) internal {
        debt.grantRole(BastionRoles.TOKEN_MINTER_ROLE, address(protocol));
        debt.grantRole(BastionRoles.TOKEN_BURNER_ROLE, address(protocol));
        debt.grantRole(BastionRoles.TOKEN_BURNER_ROLE, address(collateralAuction));
        debt.grantRole(BastionRoles.TOKEN_BURNER_ROLE, address(debtAuction));
        share.grantRole(BastionRoles.TOKEN_MINTER_ROLE, address(debtAuction));

        vaultLedger.grantRole(BastionRoles.PROTOCOL_ROLE, address(protocol));
        vaultLedger.grantRole(BastionRoles.RISK_MANAGER_ROLE, address(protocol));
        accountingEngine.grantRole(BastionRoles.PROTOCOL_ROLE, address(protocol));
        accountingEngine.grantRole(BastionRoles.AUCTIONEER_ROLE, address(collateralAuction));
        accountingEngine.grantRole(BastionRoles.AUCTIONEER_ROLE, address(debtAuction));
        feeController.grantRole(BastionRoles.PROTOCOL_ROLE, address(protocol));
        feeController.grantRole(BastionRoles.RISK_MANAGER_ROLE, address(protocol));

        collateralAuction.grantRole(BastionRoles.AUCTIONEER_ROLE, address(protocol));
        collateralAuction.grantRole(BastionRoles.RISK_MANAGER_ROLE, address(protocol));
        collateralAuction.setAccounting(address(accountingEngine));
        debtAuction.grantRole(BastionRoles.AUCTIONEER_ROLE, address(protocol));
        debtAuction.grantRole(BastionRoles.RISK_MANAGER_ROLE, address(protocol));
        debtAuction.setAccounting(address(accountingEngine));
    }

    function openDepositAndMint(
        address user,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal returns (uint256 vaultId) {
        vm.startPrank(user);
        collateral.approve(address(protocol), collateralAmount);
        vaultId = protocol.openVault(address(collateral));
        protocol.depositCollateral(vaultId, collateralAmount);
        protocol.mintDebt(vaultId, debtAmount);
        vm.stopPrank();
    }

    function openDepositOnly(
        address user,
        uint256 collateralAmount
    ) internal returns (uint256 vaultId) {
        vm.startPrank(user);
        collateral.approve(address(protocol), collateralAmount);
        vaultId = protocol.openVault(address(collateral));
        protocol.depositCollateral(vaultId, collateralAmount);
        vm.stopPrank();
    }

    function setOraclePrice(
        uint256 price
    ) internal {
        vm.prank(admin);
        oracle.postPrice(address(collateral), price);
    }

    function assertVaultDebt(
        uint256 vaultId,
        uint256 expectedDebt
    ) internal view {
        BastionTypes.Vault memory data = protocol.vault(vaultId);
        assertEq(data.debt, expectedDebt, "vault debt");
    }
}
