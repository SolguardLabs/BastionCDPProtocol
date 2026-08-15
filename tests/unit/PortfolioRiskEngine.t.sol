// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { PortfolioRiskEngine } from "../../src/risk/PortfolioRiskEngine.sol";
import { Test } from "forge-std/Test.sol";

contract PortfolioRiskEngineTest is Test {
    PortfolioRiskEngine internal engine;

    function setUp() public {
        engine = new PortfolioRiskEngine();
    }

    function testSingleCollateralStressProducesExpectedShortfall() public view {
        PortfolioRiskEngine.CollateralExposure[] memory exposures =
            new PortfolioRiskEngine.CollateralExposure[](1);
        exposures[0] = _exposure(bytes32(uint256(1)), 10e18, 2000e18, 10_000e18);

        (
            PortfolioRiskEngine.PortfolioRisk memory portfolio,
            PortfolioRiskEngine.CollateralRisk[] memory risks
        ) = engine.evaluate(exposures, _stress(), _limits());

        assertEq(risks[0].spotValue, 20_000e18);
        assertEq(risks[0].stressedValue, 13_680e18);
        assertEq(risks[0].effectiveDebt, 10_500e18);
        assertEq(risks[0].liquidationRequirement, 15_750e18);
        assertEq(risks[0].shortfall, 2070e18);
        assertEq(portfolio.totalShortfall, 2070e18);
        assertEq(portfolio.debtConcentrationHhiBps, 10_000);
        assertEq(portfolio.collateralConcentrationHhiBps, 10_000);
        assertFalse(portfolio.withinLimits);
        assertNotEq(portfolio.digest, bytes32(0));
    }

    function testDiversificationReducesConcentration() public view {
        PortfolioRiskEngine.CollateralExposure[] memory exposures =
            new PortfolioRiskEngine.CollateralExposure[](2);
        exposures[0] = _exposure(bytes32(uint256(1)), 10e18, 2000e18, 10_000e18);
        exposures[1] = _exposure(bytes32(uint256(2)), 20e18, 1000e18, 10_000e18);

        PortfolioRiskEngine.StressScenario memory scenario;
        PortfolioRiskEngine.RiskLimits memory limits = PortfolioRiskEngine.RiskLimits({
            maxSingleDebtShareBps: 6000,
            maxDebtHhiBps: 6000,
            maxCollateralHhiBps: 6000,
            minStressedCoverageBps: 15_000,
            maxDebtCeilingUtilizationBps: 9000
        });

        (
            PortfolioRiskEngine.PortfolioRisk memory portfolio,
            PortfolioRiskEngine.CollateralRisk[] memory risks
        ) = engine.evaluate(exposures, scenario, limits);

        assertEq(portfolio.totalSpotValue, 40_000e18);
        assertEq(portfolio.totalEffectiveDebt, 20_000e18);
        assertEq(portfolio.stressedCoverageBps, 20_000);
        assertEq(portfolio.debtConcentrationHhiBps, 5000);
        assertEq(portfolio.collateralConcentrationHhiBps, 5000);
        assertEq(portfolio.largestDebtShareBps, 5000);
        assertEq(risks[0].debtShareBps, 5000);
        assertEq(risks[1].debtShareBps, 5000);
        assertTrue(portfolio.withinLimits);
    }

    function testZeroDebtHasUnboundedCoverageAndNoDebtConcentration() public view {
        PortfolioRiskEngine.CollateralExposure[] memory exposures =
            new PortfolioRiskEngine.CollateralExposure[](1);
        exposures[0] = _exposure(bytes32(uint256(1)), 5e18, 2000e18, 0);

        (PortfolioRiskEngine.PortfolioRisk memory portfolio,) =
            engine.evaluate(exposures, _emptyScenario(), _singleAssetLimits());

        assertEq(portfolio.stressedCoverageBps, type(uint256).max);
        assertEq(portfolio.weightedLiquidationRatioBps, 0);
        assertEq(portfolio.debtConcentrationHhiBps, 0);
        assertEq(portfolio.largestDebtShareBps, 0);
        assertTrue(portfolio.withinLimits);
    }

    function testStressCapacityMatchesSequentialHaircuts() public view {
        uint256 stressed = engine.stressedPrice(2000e18, _stress(), 0, 10_000);
        uint256 capacity = engine.maxDebtAtStress(10e18, 2000e18, 15_000, _stress(), 0, 10_000);

        assertEq(stressed, 1368e18);
        assertEq(capacity, 9120e18);
    }

    function testLiquidationPriceRoundsUp() public view {
        uint256 price = engine.liquidationPrice(3e18, 1000e18, 15_000);
        assertEq(price, 500e18);
    }

    function testRejectsNonCanonicalCollateralOrder() public {
        PortfolioRiskEngine.CollateralExposure[] memory exposures =
            new PortfolioRiskEngine.CollateralExposure[](2);
        exposures[0] = _exposure(bytes32(uint256(2)), 10e18, 2000e18, 1000e18);
        exposures[1] = _exposure(bytes32(uint256(1)), 10e18, 2000e18, 1000e18);

        vm.expectRevert(PortfolioRiskEngine.NonCanonicalCollateralOrder.selector);
        engine.evaluate(exposures, _emptyScenario(), _singleAssetLimits());
    }

    function testScenarioDigestSeparatesDebtGrowth() public view {
        PortfolioRiskEngine.StressScenario memory first = _stress();
        PortfolioRiskEngine.StressScenario memory second = _stress();
        second.debtGrowthBps += 1;

        assertNotEq(engine.scenarioDigest(first), engine.scenarioDigest(second));
    }

    function _exposure(
        bytes32 id,
        uint256 amount,
        uint256 price,
        uint256 debt
    ) internal pure returns (PortfolioRiskEngine.CollateralExposure memory) {
        return PortfolioRiskEngine.CollateralExposure({
            collateralId: id,
            collateralAmount: amount,
            spotPrice: price,
            debt: debt,
            debtCeiling: 50_000e18,
            liquidationRatioBps: 15_000,
            liquidationPenaltyBps: 1300,
            liquidityScoreBps: 0,
            oracleConfidenceBps: 10_000
        });
    }

    function _stress() internal pure returns (PortfolioRiskEngine.StressScenario memory) {
        return PortfolioRiskEngine.StressScenario({
            priceShockBps: 2000,
            liquidityHaircutBps: 1000,
            oracleDeviationBps: 0,
            debtGrowthBps: 500,
            auctionSlippageBps: 500
        });
    }

    function _emptyScenario()
        internal
        pure
        returns (PortfolioRiskEngine.StressScenario memory scenario)
    { }

    function _limits() internal pure returns (PortfolioRiskEngine.RiskLimits memory) {
        return PortfolioRiskEngine.RiskLimits({
            maxSingleDebtShareBps: 7000,
            maxDebtHhiBps: 6000,
            maxCollateralHhiBps: 6000,
            minStressedCoverageBps: 16_000,
            maxDebtCeilingUtilizationBps: 9000
        });
    }

    function _singleAssetLimits() internal pure returns (PortfolioRiskEngine.RiskLimits memory) {
        return PortfolioRiskEngine.RiskLimits({
            maxSingleDebtShareBps: 10_000,
            maxDebtHhiBps: 10_000,
            maxCollateralHhiBps: 10_000,
            minStressedCoverageBps: 10_000,
            maxDebtCeilingUtilizationBps: 10_000
        });
    }
}
