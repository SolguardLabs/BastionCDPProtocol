// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract AccountingEngine is BastionAccessControl {
    error AmountTooLarge();

    uint256 public totalNormalizedDebt;
    uint256 public totalIssuedDebt;
    uint256 public totalRepaidDebt;
    uint256 public totalFeesAccrued;
    uint256 public totalBadDebt;
    uint256 public totalRecoveredDebt;
    uint256 public activeVaults;
    uint256 public liquidatingVaults;
    uint256 public closedVaults;

    mapping(address collateral => uint256 amount) public normalizedDebtByCollateral;
    mapping(address collateral => uint256 amount) public badDebtByCollateral;
    mapping(address collateral => uint256 amount) public recoveredDebtByCollateral;
    mapping(address collateral => uint256 amount) public feesByCollateral;

    event VaultOpened(address indexed owner, address indexed collateral, uint256 indexed vaultId);
    event VaultClosed(address indexed owner, address indexed collateral, uint256 indexed vaultId);
    event DebtIssued(address indexed collateral, uint256 amount);
    event DebtRepaid(address indexed collateral, uint256 amount);
    event FeesAccrued(address indexed collateral, uint256 amount);
    event BadDebtRecorded(address indexed collateral, uint256 amount);
    event DebtRecovered(address indexed collateral, uint256 amount);
    event VaultMovedToLiquidation(address indexed collateral, uint256 indexed vaultId);

    constructor(
        address initialOwner
    ) BastionAccessControl(initialOwner) { }

    function recordVaultOpened(
        address owner_,
        address collateral,
        uint256 vaultId
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        activeVaults += 1;
        emit VaultOpened(owner_, collateral, vaultId);
    }

    function recordVaultClosed(
        address owner_,
        address collateral,
        uint256 vaultId
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        if (activeVaults != 0) {
            activeVaults -= 1;
        }
        closedVaults += 1;
        emit VaultClosed(owner_, collateral, vaultId);
    }

    function recordVaultLiquidating(
        address collateral,
        uint256 vaultId
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        if (activeVaults != 0) {
            activeVaults -= 1;
        }
        liquidatingVaults += 1;
        emit VaultMovedToLiquidation(collateral, vaultId);
    }

    function recordLiquidationFinished() external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        if (liquidatingVaults != 0) {
            liquidatingVaults -= 1;
        }
        closedVaults += 1;
    }

    function recordDebtIssued(
        address collateral,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        totalIssuedDebt += amount;
        totalNormalizedDebt += amount;
        normalizedDebtByCollateral[collateral] += amount;
        emit DebtIssued(collateral, amount);
    }

    function recordDebtRepaid(
        address collateral,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        if (amount > totalNormalizedDebt) revert AmountTooLarge();
        if (amount > normalizedDebtByCollateral[collateral]) revert AmountTooLarge();

        totalRepaidDebt += amount;
        totalNormalizedDebt -= amount;
        normalizedDebtByCollateral[collateral] -= amount;
        emit DebtRepaid(collateral, amount);
    }

    function recordFeesAccrued(
        address collateral,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        totalFeesAccrued += amount;
        totalNormalizedDebt += amount;
        normalizedDebtByCollateral[collateral] += amount;
        feesByCollateral[collateral] += amount;
        emit FeesAccrued(collateral, amount);
    }

    function recordBadDebt(
        address collateral,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        totalBadDebt += amount;
        badDebtByCollateral[collateral] += amount;
        emit BadDebtRecorded(collateral, amount);
    }

    function recordDebtRecovered(
        address collateral,
        uint256 amount
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) {
        uint256 openBadDebt = badDebtByCollateral[collateral];
        uint256 credited = amount > openBadDebt ? openBadDebt : amount;

        if (credited != 0) {
            badDebtByCollateral[collateral] -= credited;
            totalBadDebt -= credited;
        }

        if (amount <= totalNormalizedDebt) {
            totalNormalizedDebt -= amount;
        } else {
            totalNormalizedDebt = 0;
        }

        uint256 collateralDebt = normalizedDebtByCollateral[collateral];
        if (collateralDebt != 0) {
            if (amount <= collateralDebt) {
                normalizedDebtByCollateral[collateral] = collateralDebt - amount;
            } else {
                normalizedDebtByCollateral[collateral] = 0;
            }
        }

        totalRecoveredDebt += amount;
        recoveredDebtByCollateral[collateral] += amount;
        emit DebtRecovered(collateral, amount);
    }

    function snapshot() external view returns (BastionTypes.SystemSnapshot memory) {
        return BastionTypes.SystemSnapshot({
            totalNormalizedDebt: totalNormalizedDebt,
            totalIssuedDebt: totalIssuedDebt,
            totalRepaidDebt: totalRepaidDebt,
            totalFeesAccrued: totalFeesAccrued,
            totalBadDebt: totalBadDebt,
            totalRecoveredDebt: totalRecoveredDebt,
            activeVaults: activeVaults,
            liquidatingVaults: liquidatingVaults,
            closedVaults: closedVaults
        });
    }
}
