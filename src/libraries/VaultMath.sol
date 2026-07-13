// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionTypes } from "../types/BastionTypes.sol";
import { FixedPointMath } from "./FixedPointMath.sol";

library VaultMath {
    using FixedPointMath for uint256;

    error InvalidRiskParameter();
    error UnsafeTarget();

    function debtWithFees(
        uint256 debt,
        uint256 feeIndex,
        uint256 currentIndex
    ) internal pure returns (uint256) {
        return debt + FixedPointMath.accruedFromIndex(debt, feeIndex, currentIndex);
    }

    function collateralValue(
        uint256 collateralAmount,
        uint256 price
    ) internal pure returns (uint256) {
        return FixedPointMath.collateralValue(collateralAmount, price);
    }

    function collateralizationRatioBps(
        uint256 collateralAmount,
        uint256 price,
        uint256 debt
    ) internal pure returns (uint256) {
        if (debt == 0) return type(uint256).max;
        return FixedPointMath.ratioBps(collateralValue(collateralAmount, price), debt);
    }

    function isHealthy(
        uint256 collateralAmount,
        uint256 price,
        uint256 debt,
        uint256 liquidationRatioBps
    ) internal pure returns (bool) {
        if (debt == 0) return true;
        return collateralizationRatioBps(collateralAmount, price, debt) >= liquidationRatioBps;
    }

    function maxDebtForCollateral(
        uint256 collateralAmount,
        uint256 price,
        uint256 ratioBps
    ) internal pure returns (uint256) {
        if (ratioBps < BastionTypes.BPS) revert InvalidRiskParameter();
        uint256 value = collateralValue(collateralAmount, price);
        return FixedPointMath.mulDiv(value, BastionTypes.BPS, ratioBps);
    }

    function availableDebt(
        uint256 collateralAmount,
        uint256 price,
        uint256 currentDebt,
        uint256 ratioBps
    ) internal pure returns (uint256) {
        uint256 limit = maxDebtForCollateral(collateralAmount, price, ratioBps);
        return limit > currentDebt ? limit - currentDebt : 0;
    }

    function requiredCollateral(
        uint256 debt,
        uint256 price,
        uint256 ratioBps
    ) internal pure returns (uint256) {
        if (price == 0) revert InvalidRiskParameter();
        uint256 requiredValue = FixedPointMath.mulDivUp(debt, ratioBps, BastionTypes.BPS);
        return FixedPointMath.divWadUp(requiredValue, price);
    }

    function withdrawableCollateral(
        uint256 collateralAmount,
        uint256 price,
        uint256 debt,
        uint256 ratioBps
    ) internal pure returns (uint256) {
        if (debt == 0) return collateralAmount;
        uint256 required = requiredCollateral(debt, price, ratioBps);
        return collateralAmount > required ? collateralAmount - required : 0;
    }

    function repayToTargetRatio(
        uint256 collateralAmount,
        uint256 price,
        uint256 debt,
        uint256 targetRatioBps
    ) internal pure returns (uint256) {
        if (targetRatioBps < BastionTypes.BPS) revert UnsafeTarget();
        uint256 maxDebt = maxDebtForCollateral(collateralAmount, price, targetRatioBps);
        return debt > maxDebt ? debt - maxDebt : 0;
    }

    function collateralToAddForTarget(
        uint256 collateralAmount,
        uint256 price,
        uint256 debt,
        uint256 targetRatioBps
    ) internal pure returns (uint256) {
        uint256 required = requiredCollateral(debt, price, targetRatioBps);
        return required > collateralAmount ? required - collateralAmount : 0;
    }

    function liquidationPenalty(
        uint256 debt,
        uint256 penaltyBps
    ) internal pure returns (uint256) {
        return FixedPointMath.bpUp(debt, penaltyBps);
    }

    function liquidationDebt(
        uint256 debt,
        uint256 penaltyBps
    ) internal pure returns (uint256) {
        return debt + liquidationPenalty(debt, penaltyBps);
    }

    function closeFactorDebt(
        uint256 debt,
        uint256 closeFactorBps
    ) internal pure returns (uint256) {
        if (closeFactorBps > BastionTypes.BPS) revert InvalidRiskParameter();
        if (closeFactorBps == 0) return debt;
        return FixedPointMath.bpUp(debt, closeFactorBps);
    }

    function auctionDebtPrice(
        uint256 debtRemaining,
        uint256 collateralRemaining
    ) internal pure returns (uint256) {
        if (collateralRemaining == 0) revert InvalidRiskParameter();
        return FixedPointMath.divWadUp(debtRemaining, collateralRemaining);
    }

    function auctionCollateralForDebt(
        uint256 debtAmount,
        uint256 debtRemaining,
        uint256 collateralRemaining,
        uint256 discountBps
    ) internal pure returns (uint256) {
        if (debtRemaining == 0) return 0;
        uint256 baseOut = FixedPointMath.mulDiv(debtAmount, collateralRemaining, debtRemaining);
        uint256 boosted = baseOut + FixedPointMath.bp(baseOut, discountBps);
        return FixedPointMath.min(boosted, collateralRemaining);
    }

    function auctionDebtForCollateral(
        uint256 collateralAmount,
        uint256 debtRemaining,
        uint256 collateralRemaining,
        uint256 discountBps
    ) internal pure returns (uint256) {
        if (collateralRemaining == 0) revert InvalidRiskParameter();
        uint256 adjustedCollateral = FixedPointMath.mulDivUp(
            collateralAmount, BastionTypes.BPS, BastionTypes.BPS + discountBps
        );
        return FixedPointMath.mulDivUp(adjustedCollateral, debtRemaining, collateralRemaining);
    }

    function cappedAuctionPurchase(
        uint256 requestedDebt,
        uint256 debtRemaining,
        uint256 collateralRemaining,
        uint256 discountBps
    ) internal pure returns (uint256 collateralOut, uint256 debtPaid) {
        debtPaid = FixedPointMath.min(requestedDebt, debtRemaining);
        collateralOut =
            auctionCollateralForDebt(debtPaid, debtRemaining, collateralRemaining, discountBps);
    }

    function minRepayForDebtFloor(
        uint256 debt,
        uint256 minDebt
    ) internal pure returns (uint256) {
        if (debt == 0) return 0;
        if (debt <= minDebt) return debt;
        return debt - minDebt;
    }

    function principalAfterRepay(
        uint256 debt,
        uint256 repayAmount
    ) internal pure returns (uint256) {
        return repayAmount >= debt ? 0 : debt - repayAmount;
    }

    function utilizationBps(
        uint256 totalDebt,
        uint256 debtCeiling
    ) internal pure returns (uint256) {
        if (debtCeiling == 0) revert InvalidRiskParameter();
        return FixedPointMath.ratioBps(totalDebt, debtCeiling);
    }

    function capacityAfterMint(
        uint256 totalDebt,
        uint256 debtCeiling,
        uint256 mintAmount
    ) internal pure returns (uint256) {
        if (totalDebt + mintAmount >= debtCeiling) return 0;
        return debtCeiling - totalDebt - mintAmount;
    }

    function canMintWithinCeiling(
        uint256 totalDebt,
        uint256 debtCeiling,
        uint256 mintAmount
    ) internal pure returns (bool) {
        return totalDebt + mintAmount <= debtCeiling;
    }

    function isDustFree(
        uint256 debt,
        uint256 minDebt
    ) internal pure returns (bool) {
        return debt == 0 || debt >= minDebt;
    }

    function requiredPriceForRatio(
        uint256 collateralAmount,
        uint256 debt,
        uint256 ratioBps
    ) internal pure returns (uint256) {
        if (collateralAmount == 0) return type(uint256).max;
        uint256 requiredValue = FixedPointMath.mulDivUp(debt, ratioBps, BastionTypes.BPS);
        return FixedPointMath.divWadUp(requiredValue, collateralAmount);
    }

    function priceBufferBps(
        uint256 collateralAmount,
        uint256 price,
        uint256 debt,
        uint256 liquidationRatioBps
    ) internal pure returns (uint256) {
        uint256 required = requiredPriceForRatio(collateralAmount, debt, liquidationRatioBps);
        if (required == 0 || required == type(uint256).max) return type(uint256).max;
        if (price <= required) return 0;
        return FixedPointMath.ratioBps(price - required, required);
    }
}
