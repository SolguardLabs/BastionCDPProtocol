// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IBastionOracle } from "../interfaces/IBastionOracle.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract RiskEngine {
    using FixedPointMath for uint256;

    error CollateralDisabled();
    error StalePrice(address collateral);
    error InvalidCollateralConfig();
    error VaultWouldBeUnsafe();
    error DebtBelowMinimum();
    error DebtCeilingExceeded();

    function validateConfig(
        BastionTypes.CollateralConfig memory config
    ) external pure {
        if (config.token == address(0)) revert InvalidCollateralConfig();
        if (config.oracle == address(0)) revert InvalidCollateralConfig();
        if (config.liquidationRatioBps < BastionTypes.BPS) revert InvalidCollateralConfig();
        if (config.closeFactorBps > BastionTypes.BPS) revert InvalidCollateralConfig();
        if (config.auctionDiscountBps > 5000) revert InvalidCollateralConfig();
    }

    function priceOf(
        BastionTypes.CollateralConfig memory config
    ) public view returns (uint256) {
        if (!config.enabled) revert CollateralDisabled();

        (uint256 price, uint256 updatedAt) = IBastionOracle(config.oracle).latestPrice(config.token);
        // forge-lint: disable-next-line(block-timestamp)
        if (price == 0 || block.timestamp > updatedAt + config.maxPriceAge) {
            revert StalePrice(config.token);
        }

        return price;
    }

    function collateralValue(
        BastionTypes.CollateralConfig memory config,
        uint256 collateralAmount
    ) public view returns (uint256) {
        return FixedPointMath.collateralValue(collateralAmount, priceOf(config));
    }

    function liquidationDebt(
        BastionTypes.CollateralConfig memory config,
        uint256 debt
    ) public pure returns (uint256) {
        return FixedPointMath.liquidationDebt(debt, config.liquidationPenaltyBps);
    }

    function healthRatioBps(
        BastionTypes.CollateralConfig memory config,
        uint256 collateralAmount,
        uint256 debt
    ) public view returns (uint256) {
        if (debt == 0) return type(uint256).max;
        uint256 value = collateralValue(config, collateralAmount);
        return FixedPointMath.ratioBps(value, debt);
    }

    function isHealthy(
        BastionTypes.CollateralConfig memory config,
        uint256 collateralAmount,
        uint256 debt
    ) public view returns (bool) {
        if (debt == 0) return true;
        uint256 value = collateralValue(config, collateralAmount);
        return FixedPointMath.isRatioAtLeast(value, debt, config.liquidationRatioBps);
    }

    function maxDebt(
        BastionTypes.CollateralConfig memory config,
        uint256 collateralAmount
    ) public view returns (uint256) {
        uint256 value = collateralValue(config, collateralAmount);
        return FixedPointMath.mulDiv(value, BastionTypes.BPS, config.liquidationRatioBps);
    }

    function liquidationPrice(
        BastionTypes.CollateralConfig memory config,
        uint256 collateralAmount,
        uint256 debt
    ) external pure returns (uint256) {
        if (collateralAmount == 0) return 0;
        uint256 requiredValue =
            FixedPointMath.mulDivUp(debt, config.liquidationRatioBps, BastionTypes.BPS);
        return FixedPointMath.divWadUp(requiredValue, collateralAmount);
    }

    function validateMint(
        BastionTypes.CollateralConfig memory config,
        uint256 collateralAmount,
        uint256 existingDebt,
        uint256 mintAmount,
        uint256 totalDebtForCollateral
    ) external view {
        if (!config.enabled) revert CollateralDisabled();
        uint256 newDebt = existingDebt + mintAmount;
        if (newDebt < config.minDebt) revert DebtBelowMinimum();
        if (totalDebtForCollateral + mintAmount > config.debtCeiling) revert DebtCeilingExceeded();
        if (!isHealthy(config, collateralAmount, newDebt)) revert VaultWouldBeUnsafe();
    }

    function validateWithdrawal(
        BastionTypes.CollateralConfig memory config,
        uint256 collateralBefore,
        uint256 withdrawAmount,
        uint256 debt
    ) external view {
        if (withdrawAmount > collateralBefore) revert VaultWouldBeUnsafe();
        uint256 collateralAfter = collateralBefore - withdrawAmount;
        if (!isHealthy(config, collateralAfter, debt)) revert VaultWouldBeUnsafe();
    }

    function validateDebtState(
        BastionTypes.CollateralConfig memory config,
        uint256 debt
    ) external pure {
        if (debt != 0 && debt < config.minDebt) revert DebtBelowMinimum();
    }
}
