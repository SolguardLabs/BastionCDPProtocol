// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract PortfolioRiskEngine {
    using FixedPointMath for uint256;

    error EmptyPortfolio();
    error InvalidCollateral();
    error InvalidScenario();
    error InvalidLimits();
    error NonCanonicalCollateralOrder();

    struct CollateralExposure {
        bytes32 collateralId;
        uint256 collateralAmount;
        uint256 spotPrice;
        uint256 debt;
        uint256 debtCeiling;
        uint256 liquidationRatioBps;
        uint256 liquidationPenaltyBps;
        uint256 liquidityScoreBps;
        uint256 oracleConfidenceBps;
    }

    struct StressScenario {
        uint256 priceShockBps;
        uint256 liquidityHaircutBps;
        uint256 oracleDeviationBps;
        uint256 debtGrowthBps;
        uint256 auctionSlippageBps;
    }

    struct RiskLimits {
        uint256 maxSingleDebtShareBps;
        uint256 maxDebtHhiBps;
        uint256 maxCollateralHhiBps;
        uint256 minStressedCoverageBps;
        uint256 maxDebtCeilingUtilizationBps;
    }

    struct CollateralRisk {
        bytes32 collateralId;
        uint256 spotValue;
        uint256 stressedValue;
        uint256 effectiveDebt;
        uint256 liquidationRequirement;
        uint256 shortfall;
        uint256 debtShareBps;
        uint256 collateralShareBps;
        uint256 ceilingUtilizationBps;
        uint256 liquidationPrice;
        uint256 capitalAtRisk;
    }

    struct PortfolioRisk {
        uint256 totalSpotValue;
        uint256 totalStressedValue;
        uint256 totalEffectiveDebt;
        uint256 totalDebtCeiling;
        uint256 totalLiquidationRequirement;
        uint256 totalShortfall;
        uint256 stressedCoverageBps;
        uint256 weightedLiquidationRatioBps;
        uint256 debtCeilingUtilizationBps;
        uint256 debtConcentrationHhiBps;
        uint256 collateralConcentrationHhiBps;
        uint256 largestDebtShareBps;
        uint256 riskScoreBps;
        bool withinLimits;
        bytes32 digest;
    }

    function evaluate(
        CollateralExposure[] calldata exposures,
        StressScenario calldata scenario,
        RiskLimits calldata limits
    ) external pure returns (PortfolioRisk memory portfolio, CollateralRisk[] memory risks) {
        _validateScenario(scenario);
        _validateLimits(limits);
        if (exposures.length == 0) revert EmptyPortfolio();

        risks = new CollateralRisk[](exposures.length);
        bytes32 previousId;

        for (uint256 i; i < exposures.length; ++i) {
            CollateralExposure calldata exposure = exposures[i];
            _validateExposure(exposure);

            if (i != 0 && uint256(exposure.collateralId) <= uint256(previousId)) {
                revert NonCanonicalCollateralOrder();
            }
            previousId = exposure.collateralId;

            CollateralRisk memory risk = _evaluateCollateral(exposure, scenario);
            risks[i] = risk;

            portfolio.totalSpotValue += risk.spotValue;
            portfolio.totalStressedValue += risk.stressedValue;
            portfolio.totalEffectiveDebt += risk.effectiveDebt;
            portfolio.totalDebtCeiling += exposure.debtCeiling;
            portfolio.totalLiquidationRequirement += risk.liquidationRequirement;
            portfolio.totalShortfall += risk.shortfall;
            portfolio.weightedLiquidationRatioBps += risk.effectiveDebt
            * exposure.liquidationRatioBps;
        }

        if (portfolio.totalEffectiveDebt == 0) {
            portfolio.stressedCoverageBps = type(uint256).max;
            portfolio.weightedLiquidationRatioBps = 0;
        } else {
            portfolio.stressedCoverageBps = FixedPointMath.ratioBps(
                portfolio.totalStressedValue, portfolio.totalEffectiveDebt
            );
            portfolio.weightedLiquidationRatioBps = FixedPointMath.mulDiv(
                portfolio.weightedLiquidationRatioBps, 1, portfolio.totalEffectiveDebt
            );
        }

        portfolio.debtCeilingUtilizationBps = portfolio.totalDebtCeiling == 0
            ? 0
            : FixedPointMath.ratioBps(portfolio.totalEffectiveDebt, portfolio.totalDebtCeiling);

        for (uint256 i; i < risks.length; ++i) {
            CollateralRisk memory risk = risks[i];
            risk.debtShareBps = portfolio.totalEffectiveDebt == 0
                ? 0
                : FixedPointMath.ratioBps(risk.effectiveDebt, portfolio.totalEffectiveDebt);
            risk.collateralShareBps = portfolio.totalSpotValue == 0
                ? 0
                : FixedPointMath.ratioBps(risk.spotValue, portfolio.totalSpotValue);

            portfolio.debtConcentrationHhiBps += FixedPointMath.mulDiv(
                risk.debtShareBps, risk.debtShareBps, BastionTypes.BPS
            );
            portfolio.collateralConcentrationHhiBps += FixedPointMath.mulDiv(
                risk.collateralShareBps, risk.collateralShareBps, BastionTypes.BPS
            );
            portfolio.largestDebtShareBps =
                FixedPointMath.max(portfolio.largestDebtShareBps, risk.debtShareBps);
            risks[i] = risk;
        }

        portfolio.riskScoreBps = _riskScore(portfolio, limits);
        portfolio.withinLimits = portfolio.totalShortfall == 0
            && portfolio.largestDebtShareBps <= limits.maxSingleDebtShareBps
            && portfolio.debtConcentrationHhiBps <= limits.maxDebtHhiBps
            && portfolio.collateralConcentrationHhiBps <= limits.maxCollateralHhiBps
            && portfolio.stressedCoverageBps >= limits.minStressedCoverageBps
            && portfolio.debtCeilingUtilizationBps <= limits.maxDebtCeilingUtilizationBps;
        portfolio.digest = keccak256(
            abi.encode(
                keccak256("BASTION_PORTFOLIO_RISK_V1"),
                exposures,
                scenario,
                limits,
                portfolio.totalSpotValue,
                portfolio.totalStressedValue,
                portfolio.totalEffectiveDebt,
                portfolio.totalShortfall,
                portfolio.riskScoreBps
            )
        );
    }

    function previewCollateral(
        CollateralExposure calldata exposure,
        StressScenario calldata scenario
    ) external pure returns (CollateralRisk memory) {
        _validateScenario(scenario);
        _validateExposure(exposure);
        return _evaluateCollateral(exposure, scenario);
    }

    function stressedPrice(
        uint256 spotPrice,
        StressScenario calldata scenario,
        uint256 liquidityScoreBps,
        uint256 oracleConfidenceBps
    ) public pure returns (uint256) {
        _validateScenario(scenario);
        if (spotPrice == 0 || liquidityScoreBps > BastionTypes.BPS) {
            revert InvalidCollateral();
        }
        if (oracleConfidenceBps > BastionTypes.BPS) revert InvalidCollateral();

        uint256 value = _applyHaircut(spotPrice, scenario.priceShockBps);
        uint256 liquidityPenalty = FixedPointMath.mulDiv(
            scenario.liquidityHaircutBps, BastionTypes.BPS - liquidityScoreBps, BastionTypes.BPS
        );
        uint256 oraclePenalty = FixedPointMath.mulDiv(
            scenario.oracleDeviationBps, BastionTypes.BPS - oracleConfidenceBps, BastionTypes.BPS
        );

        value = _applyHaircut(value, liquidityPenalty);
        value = _applyHaircut(value, oraclePenalty);
        return _applyHaircut(value, scenario.auctionSlippageBps);
    }

    function maxDebtAtStress(
        uint256 collateralAmount,
        uint256 spotPrice,
        uint256 liquidationRatioBps,
        StressScenario calldata scenario,
        uint256 liquidityScoreBps,
        uint256 oracleConfidenceBps
    ) external pure returns (uint256) {
        if (liquidationRatioBps < BastionTypes.BPS) revert InvalidCollateral();
        uint256 value = FixedPointMath.collateralValue(
            collateralAmount,
            stressedPrice(spotPrice, scenario, liquidityScoreBps, oracleConfidenceBps)
        );
        return FixedPointMath.mulDiv(value, BastionTypes.BPS, liquidationRatioBps);
    }

    function liquidationPrice(
        uint256 collateralAmount,
        uint256 debt,
        uint256 liquidationRatioBps
    ) public pure returns (uint256) {
        if (collateralAmount == 0) return debt == 0 ? 0 : type(uint256).max;
        if (liquidationRatioBps < BastionTypes.BPS) revert InvalidCollateral();
        uint256 requiredValue = FixedPointMath.mulDivUp(debt, liquidationRatioBps, BastionTypes.BPS);
        return FixedPointMath.divWadUp(requiredValue, collateralAmount);
    }

    function scenarioDigest(
        StressScenario calldata scenario
    ) external pure returns (bytes32) {
        _validateScenario(scenario);
        return keccak256(abi.encode(keccak256("BASTION_STRESS_SCENARIO_V1"), scenario));
    }

    function _evaluateCollateral(
        CollateralExposure calldata exposure,
        StressScenario calldata scenario
    ) internal pure returns (CollateralRisk memory risk) {
        risk.collateralId = exposure.collateralId;
        risk.spotValue =
            FixedPointMath.collateralValue(exposure.collateralAmount, exposure.spotPrice);
        uint256 stressPrice = stressedPrice(
            exposure.spotPrice, scenario, exposure.liquidityScoreBps, exposure.oracleConfidenceBps
        );
        risk.stressedValue = FixedPointMath.collateralValue(exposure.collateralAmount, stressPrice);
        risk.effectiveDebt = FixedPointMath.mulDivUp(
            exposure.debt, BastionTypes.BPS + scenario.debtGrowthBps, BastionTypes.BPS
        );
        risk.liquidationRequirement = FixedPointMath.mulDivUp(
            risk.effectiveDebt, exposure.liquidationRatioBps, BastionTypes.BPS
        );
        risk.shortfall = risk.liquidationRequirement > risk.stressedValue
            ? risk.liquidationRequirement - risk.stressedValue
            : 0;
        risk.ceilingUtilizationBps =
            FixedPointMath.ratioBps(risk.effectiveDebt, exposure.debtCeiling);
        risk.liquidationPrice = liquidationPrice(
            exposure.collateralAmount, risk.effectiveDebt, exposure.liquidationRatioBps
        );

        uint256 recoverableValue = FixedPointMath.mulDiv(
            risk.stressedValue, BastionTypes.BPS - exposure.liquidationPenaltyBps, BastionTypes.BPS
        );
        risk.capitalAtRisk =
            risk.effectiveDebt > recoverableValue ? risk.effectiveDebt - recoverableValue : 0;
    }

    function _riskScore(
        PortfolioRisk memory portfolio,
        RiskLimits calldata limits
    ) internal pure returns (uint256) {
        uint256 score;

        if (portfolio.totalLiquidationRequirement != 0) {
            score += FixedPointMath.ratioBps(
                portfolio.totalShortfall, portfolio.totalLiquidationRequirement
            );
        }
        if (portfolio.debtConcentrationHhiBps > limits.maxDebtHhiBps) {
            score += portfolio.debtConcentrationHhiBps - limits.maxDebtHhiBps;
        }
        if (portfolio.collateralConcentrationHhiBps > limits.maxCollateralHhiBps) {
            score += portfolio.collateralConcentrationHhiBps - limits.maxCollateralHhiBps;
        }
        if (portfolio.largestDebtShareBps > limits.maxSingleDebtShareBps) {
            score += portfolio.largestDebtShareBps - limits.maxSingleDebtShareBps;
        }
        if (
            portfolio.stressedCoverageBps != type(uint256).max
                && portfolio.stressedCoverageBps < limits.minStressedCoverageBps
        ) {
            score += limits.minStressedCoverageBps - portfolio.stressedCoverageBps;
        }
        if (portfolio.debtCeilingUtilizationBps > limits.maxDebtCeilingUtilizationBps) {
            score += portfolio.debtCeilingUtilizationBps - limits.maxDebtCeilingUtilizationBps;
        }

        return FixedPointMath.min(score, BastionTypes.BPS);
    }

    function _validateExposure(
        CollateralExposure calldata exposure
    ) internal pure {
        if (exposure.collateralId == bytes32(0)) revert InvalidCollateral();
        if (exposure.spotPrice == 0 || exposure.debtCeiling == 0) revert InvalidCollateral();
        if (exposure.liquidationRatioBps < BastionTypes.BPS) revert InvalidCollateral();
        if (exposure.liquidationPenaltyBps > 5000) revert InvalidCollateral();
        if (exposure.liquidityScoreBps > BastionTypes.BPS) revert InvalidCollateral();
        if (exposure.oracleConfidenceBps > BastionTypes.BPS) revert InvalidCollateral();
    }

    function _validateScenario(
        StressScenario calldata scenario
    ) internal pure {
        if (scenario.priceShockBps > BastionTypes.BPS) revert InvalidScenario();
        if (scenario.liquidityHaircutBps > BastionTypes.BPS) revert InvalidScenario();
        if (scenario.oracleDeviationBps > BastionTypes.BPS) revert InvalidScenario();
        if (scenario.debtGrowthBps > BastionTypes.BPS) revert InvalidScenario();
        if (scenario.auctionSlippageBps > BastionTypes.BPS) revert InvalidScenario();
    }

    function _validateLimits(
        RiskLimits calldata limits
    ) internal pure {
        if (limits.maxSingleDebtShareBps == 0 || limits.maxSingleDebtShareBps > BastionTypes.BPS) {
            revert InvalidLimits();
        }
        if (limits.maxDebtHhiBps == 0 || limits.maxDebtHhiBps > BastionTypes.BPS) {
            revert InvalidLimits();
        }
        if (limits.maxCollateralHhiBps == 0 || limits.maxCollateralHhiBps > BastionTypes.BPS) {
            revert InvalidLimits();
        }
        if (
            limits.minStressedCoverageBps < BastionTypes.BPS
                || limits.minStressedCoverageBps > 50_000
        ) revert InvalidLimits();
        if (
            limits.maxDebtCeilingUtilizationBps == 0
                || limits.maxDebtCeilingUtilizationBps > BastionTypes.BPS
        ) revert InvalidLimits();
    }

    function _applyHaircut(
        uint256 value,
        uint256 haircutBps
    ) internal pure returns (uint256) {
        return FixedPointMath.mulDiv(value, BastionTypes.BPS - haircutBps, BastionTypes.BPS);
    }
}
