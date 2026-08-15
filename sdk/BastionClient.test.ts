import assert from "node:assert/strict";
import test from "node:test";

import {
  BPS,
  BastionClient,
  RAY,
  WAD,
  YEAR_SECONDS,
  accrueLinear,
  accruedFromIndex,
  evaluatePortfolio,
  formatUnits,
  liquidationDebt,
  liquidationPrice,
  mulDivUp,
  parseUnits,
  serializeBigInts,
  stressedPrice,
  type Address,
  type CollateralExposure,
  type ContractReader,
  type ModuleAddresses,
  type ReadContractRequest,
  type RiskLimits,
  type StressScenario,
} from "./BastionClient.js";

const id = (value: number): `0x${string}` => `0x${value.toString(16).padStart(64, "0")}`;

const scenario: StressScenario = {
  priceShockBps: 2000n,
  liquidityHaircutBps: 1000n,
  oracleDeviationBps: 0n,
  debtGrowthBps: 500n,
  auctionSlippageBps: 500n,
};

const limits: RiskLimits = {
  maxSingleDebtShareBps: 6000n,
  maxDebtHhiBps: 6000n,
  maxCollateralHhiBps: 6000n,
  minStressedCoverageBps: 15_000n,
  maxDebtCeilingUtilizationBps: 9000n,
};

const exposure = (
  collateralId: `0x${string}`,
  amount: bigint,
  price: bigint,
  debt: bigint,
): CollateralExposure => ({
  collateralId,
  collateralAmount: amount,
  spotPrice: price,
  debt,
  debtCeiling: 50_000n * WAD,
  liquidationRatioBps: 15_000n,
  liquidationPenaltyBps: 1300n,
  liquidityScoreBps: 0n,
  oracleConfidenceBps: BPS,
});

test("parses and formats exact token units", () => {
  const value = parseUnits("1234.000000000000000001");
  assert.equal(value, 1234n * WAD + 1n);
  assert.equal(formatUnits(value), "1234.000000000000000001");
  assert.equal(formatUnits(parseUnits("42.500000", 6), 6), "42.5");
});

test("rejects precision loss", () => {
  assert.throws(() => parseUnits("1.0000001", 6), /precision/);
  assert.throws(() => parseUnits("-1", 18), /unsigned/);
});

test("rounds debt requirements upward", () => {
  assert.equal(mulDivUp(10n, 1n, 3n), 4n);
  assert.equal(liquidationDebt(1000n * WAD, 1300n), 1130n * WAD);
  assert.equal(liquidationPrice(3n * WAD, 1000n * WAD, 15_000n), 500n * WAD);
});

test("matches one year of linear fee accrual", () => {
  const next = accrueLinear(RAY, 500n, YEAR_SECONDS);
  assert.equal(next, 105n * 10n ** 25n);
  assert.equal(accruedFromIndex(10_000n * WAD, RAY, next), 500n * WAD);
});

test("applies stress haircuts sequentially", () => {
  assert.equal(stressedPrice(2000n * WAD, scenario, 0n, BPS), 1368n * WAD);
});

test("computes diversified portfolio concentration", () => {
  const emptyStress: StressScenario = {
    priceShockBps: 0n,
    liquidityHaircutBps: 0n,
    oracleDeviationBps: 0n,
    debtGrowthBps: 0n,
    auctionSlippageBps: 0n,
  };
  const result = evaluatePortfolio(
    [
      exposure(id(1), 10n * WAD, 2000n * WAD, 10_000n * WAD),
      exposure(id(2), 20n * WAD, 1000n * WAD, 10_000n * WAD),
    ],
    emptyStress,
    limits,
  );

  assert.equal(result.portfolio.totalSpotValue, 40_000n * WAD);
  assert.equal(result.portfolio.stressedCoverageBps, 20_000n);
  assert.equal(result.portfolio.debtConcentrationHhiBps, 5000n);
  assert.equal(result.portfolio.collateralConcentrationHhiBps, 5000n);
  assert.equal(result.portfolio.withinLimits, true);
});

test("detects stressed liquidation shortfall", () => {
  const result = evaluatePortfolio(
    [exposure(id(1), 10n * WAD, 2000n * WAD, 10_000n * WAD)],
    scenario,
    { ...limits, maxSingleDebtShareBps: BPS, maxDebtHhiBps: BPS, maxCollateralHhiBps: BPS },
  );
  assert.equal(result.collaterals[0]?.stressedValue, 13_680n * WAD);
  assert.equal(result.portfolio.totalShortfall, 2070n * WAD);
  assert.equal(result.portfolio.withinLimits, false);
});

test("requires canonical collateral identifiers", () => {
  assert.throws(
    () =>
      evaluatePortfolio(
        [exposure(id(2), WAD, WAD, 0n), exposure(id(1), WAD, WAD, 0n)],
        scenario,
        limits,
      ),
    /canonical/,
  );
});

test("serializes bigint metrics without precision loss", () => {
  assert.equal(
    serializeBigInts({ debt: 10_000n * WAD, healthy: true }),
    `{"debt":"10000000000000000000000","healthy":true}`,
  );
});

test("client resolves module addresses before accounting and ledger reads", async () => {
  const protocol = "0x0000000000000000000000000000000000000001" as Address;
  const owner = "0x0000000000000000000000000000000000000002" as Address;
  const modules: ModuleAddresses = {
    debt: "0x0000000000000000000000000000000000000010",
    share: "0x0000000000000000000000000000000000000011",
    vaultLedger: "0x0000000000000000000000000000000000000012",
    accountingEngine: "0x0000000000000000000000000000000000000013",
    fees: "0x0000000000000000000000000000000000000014",
    collateralAuction: "0x0000000000000000000000000000000000000015",
    debtAuction: "0x0000000000000000000000000000000000000016",
  };
  const calls: ReadContractRequest[] = [];
  const reader: ContractReader = {
    async readContract<T>(request: ReadContractRequest): Promise<T> {
      calls.push(request);
      if (request.functionName === "moduleAddresses") return modules as T;
      if (request.functionName === "vaultsOf") return [1n, 7n] as T;
      return { totalNormalizedDebt: 123n } as T;
    },
  };
  const client = new BastionClient(protocol, reader);

  assert.deepEqual(await client.vaultIdsOf(owner), [1n, 7n]);
  assert.equal((await client.systemSnapshot()).totalNormalizedDebt, 123n);
  assert.deepEqual(
    calls.map((call) => call.functionName),
    ["moduleAddresses", "vaultsOf", "moduleAddresses", "snapshot"],
  );
  assert.equal(calls[1]?.address, modules.vaultLedger);
  assert.equal(calls[3]?.address, modules.accountingEngine);
});
