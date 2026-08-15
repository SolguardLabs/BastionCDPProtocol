export const WAD = 10n ** 18n;
export const RAY = 10n ** 27n;
export const BPS = 10_000n;
export const YEAR_SECONDS = 365n * 24n * 60n * 60n;

export type Address = `0x${string}`;
export type Hex = `0x${string}`;

export interface ReadContractRequest {
  address: Address;
  abi: readonly unknown[];
  functionName: string;
  args?: readonly unknown[];
}

export interface ContractReader {
  readContract<T>(request: ReadContractRequest): Promise<T>;
}

export interface Vault {
  id: bigint;
  owner: Address;
  collateralToken: Address;
  collateralAmount: bigint;
  debt: bigint;
  feeIndex: bigint;
  openedAt: bigint;
  updatedAt: bigint;
  status: number;
}

export interface CollateralConfig {
  enabled: boolean;
  token: Address;
  oracle: Address;
  debtCeiling: bigint;
  minDebt: bigint;
  liquidationRatioBps: bigint;
  liquidationPenaltyBps: bigint;
  maxPriceAge: bigint;
  auctionDiscountBps: bigint;
  closeFactorBps: bigint;
  symbol: string;
}

export interface VaultView {
  vault: Vault;
  collateral: CollateralConfig;
  collateralPrice: bigint;
  collateralValue: bigint;
  liquidationDebt: bigint;
  pendingFees: bigint;
  healthy: boolean;
}

export interface SystemSnapshot {
  totalNormalizedDebt: bigint;
  totalIssuedDebt: bigint;
  totalRepaidDebt: bigint;
  totalFeesAccrued: bigint;
  totalBadDebt: bigint;
  totalRecoveredDebt: bigint;
  activeVaults: bigint;
  liquidatingVaults: bigint;
  closedVaults: bigint;
}

export interface ModuleAddresses {
  debt: Address;
  share: Address;
  vaultLedger: Address;
  accountingEngine: Address;
  fees: Address;
  collateralAuction: Address;
  debtAuction: Address;
}

export interface CollateralExposure {
  collateralId: Hex;
  collateralAmount: bigint;
  spotPrice: bigint;
  debt: bigint;
  debtCeiling: bigint;
  liquidationRatioBps: bigint;
  liquidationPenaltyBps: bigint;
  liquidityScoreBps: bigint;
  oracleConfidenceBps: bigint;
}

export interface StressScenario {
  priceShockBps: bigint;
  liquidityHaircutBps: bigint;
  oracleDeviationBps: bigint;
  debtGrowthBps: bigint;
  auctionSlippageBps: bigint;
}

export interface RiskLimits {
  maxSingleDebtShareBps: bigint;
  maxDebtHhiBps: bigint;
  maxCollateralHhiBps: bigint;
  minStressedCoverageBps: bigint;
  maxDebtCeilingUtilizationBps: bigint;
}

export interface CollateralRisk {
  collateralId: Hex;
  spotValue: bigint;
  stressedValue: bigint;
  effectiveDebt: bigint;
  liquidationRequirement: bigint;
  shortfall: bigint;
  debtShareBps: bigint;
  collateralShareBps: bigint;
  ceilingUtilizationBps: bigint;
  liquidationPrice: bigint;
  capitalAtRisk: bigint;
}

export interface PortfolioRisk {
  totalSpotValue: bigint;
  totalStressedValue: bigint;
  totalEffectiveDebt: bigint;
  totalDebtCeiling: bigint;
  totalLiquidationRequirement: bigint;
  totalShortfall: bigint;
  stressedCoverageBps: bigint;
  weightedLiquidationRatioBps: bigint;
  debtCeilingUtilizationBps: bigint;
  debtConcentrationHhiBps: bigint;
  collateralConcentrationHhiBps: bigint;
  largestDebtShareBps: bigint;
  riskScoreBps: bigint;
  withinLimits: boolean;
}

export interface PortfolioEvaluation {
  portfolio: PortfolioRisk;
  collaterals: CollateralRisk[];
}

const protocolAbi = [
  {
    type: "function",
    name: "vault",
    stateMutability: "view",
    inputs: [{ name: "vaultId", type: "uint256" }],
    outputs: [{ name: "", type: "tuple" }],
  },
  {
    type: "function",
    name: "vaultView",
    stateMutability: "view",
    inputs: [{ name: "vaultId", type: "uint256" }],
    outputs: [{ name: "", type: "tuple" }],
  },
  {
    type: "function",
    name: "collateralConfig",
    stateMutability: "view",
    inputs: [{ name: "collateralToken", type: "address" }],
    outputs: [{ name: "", type: "tuple" }],
  },
  {
    type: "function",
    name: "moduleAddresses",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "tuple" }],
  },
] as const;

const accountingAbi = [
  {
    type: "function",
    name: "snapshot",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "tuple" }],
  },
] as const;

const ledgerAbi = [
  {
    type: "function",
    name: "vaultsOf",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "", type: "uint256[]" }],
  },
] as const;

function assertUnsigned(value: bigint, label: string): void {
  if (value < 0n) throw new RangeError(`${label} must be unsigned`);
}

function assertBps(value: bigint, label: string): void {
  assertUnsigned(value, label);
  if (value > BPS) throw new RangeError(`${label} exceeds 10,000 bps`);
}

export function mulDiv(x: bigint, y: bigint, denominator: bigint): bigint {
  assertUnsigned(x, "x");
  assertUnsigned(y, "y");
  if (denominator <= 0n) throw new RangeError("denominator must be positive");
  return (x * y) / denominator;
}

export function mulDivUp(x: bigint, y: bigint, denominator: bigint): bigint {
  const floor = mulDiv(x, y, denominator);
  return (x * y) % denominator === 0n ? floor : floor + 1n;
}

export function ratioBps(numerator: bigint, denominator: bigint): bigint {
  if (denominator <= 0n) throw new RangeError("denominator must be positive");
  return mulDiv(numerator, BPS, denominator);
}

export function parseUnits(value: string, decimals = 18): bigint {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 255) {
    throw new RangeError("decimals must be an integer between 0 and 255");
  }
  const match = /^(0|[1-9]\d*)(?:\.(\d*))?$/.exec(value.trim());
  if (!match) throw new TypeError("value must be an unsigned decimal string");
  const whole = match[1] ?? "0";
  const fraction = match[2] ?? "";
  if (fraction.length > decimals) throw new RangeError("fraction exceeds token precision");
  return BigInt(whole) * 10n ** BigInt(decimals) + BigInt(fraction.padEnd(decimals, "0") || "0");
}

export function formatUnits(value: bigint, decimals = 18): string {
  assertUnsigned(value, "value");
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 255) {
    throw new RangeError("decimals must be an integer between 0 and 255");
  }
  if (decimals === 0) return value.toString();
  const scale = 10n ** BigInt(decimals);
  const whole = value / scale;
  const fraction = (value % scale).toString().padStart(decimals, "0").replace(/0+$/, "");
  return fraction.length === 0 ? whole.toString() : `${whole}.${fraction}`;
}

export function accrueLinear(index: bigint, annualRateBps: bigint, elapsedSeconds: bigint): bigint {
  assertUnsigned(index, "index");
  assertBps(annualRateBps, "annualRateBps");
  assertUnsigned(elapsedSeconds, "elapsedSeconds");
  if (annualRateBps === 0n || elapsedSeconds === 0n) return index;
  return index + mulDiv(index, annualRateBps * elapsedSeconds, BPS * YEAR_SECONDS);
}

export function accruedFromIndex(debt: bigint, fromIndex: bigint, toIndex: bigint): bigint {
  assertUnsigned(debt, "debt");
  if (fromIndex <= 0n) throw new RangeError("fromIndex must be positive");
  if (toIndex <= fromIndex || debt === 0n) return 0n;
  return mulDivUp(debt, toIndex, fromIndex) - debt;
}

export function liquidationDebt(debt: bigint, penaltyBps: bigint): bigint {
  assertBps(penaltyBps, "penaltyBps");
  return debt + mulDivUp(debt, penaltyBps, BPS);
}

export function collateralValue(amount: bigint, price: bigint): bigint {
  return mulDiv(amount, price, WAD);
}

export function liquidationPrice(
  collateralAmount: bigint,
  debt: bigint,
  liquidationRatioBps: bigint,
): bigint {
  if (collateralAmount === 0n) return debt === 0n ? 0n : (1n << 256n) - 1n;
  if (liquidationRatioBps < BPS) throw new RangeError("liquidation ratio must be at least 100% ");
  const requiredValue = mulDivUp(debt, liquidationRatioBps, BPS);
  return mulDivUp(requiredValue, WAD, collateralAmount);
}

function applyHaircut(value: bigint, haircutBps: bigint): bigint {
  assertBps(haircutBps, "haircutBps");
  return mulDiv(value, BPS - haircutBps, BPS);
}

export function stressedPrice(
  spotPrice: bigint,
  scenario: StressScenario,
  liquidityScoreBps: bigint,
  oracleConfidenceBps: bigint,
): bigint {
  if (spotPrice <= 0n) throw new RangeError("spotPrice must be positive");
  assertBps(liquidityScoreBps, "liquidityScoreBps");
  assertBps(oracleConfidenceBps, "oracleConfidenceBps");
  assertScenario(scenario);

  const liquidityPenalty = mulDiv(scenario.liquidityHaircutBps, BPS - liquidityScoreBps, BPS);
  const oraclePenalty = mulDiv(scenario.oracleDeviationBps, BPS - oracleConfidenceBps, BPS);

  let value = applyHaircut(spotPrice, scenario.priceShockBps);
  value = applyHaircut(value, liquidityPenalty);
  value = applyHaircut(value, oraclePenalty);
  return applyHaircut(value, scenario.auctionSlippageBps);
}

export function evaluatePortfolio(
  exposures: readonly CollateralExposure[],
  scenario: StressScenario,
  limits: RiskLimits,
): PortfolioEvaluation {
  if (exposures.length === 0) throw new RangeError("portfolio cannot be empty");
  assertScenario(scenario);
  assertLimits(limits);

  let previous = "";
  const collaterals = exposures.map((exposure) => {
    assertExposure(exposure);
    const id = exposure.collateralId.toLowerCase();
    if (previous !== "" && id <= previous) throw new RangeError("collateral ids must be canonical");
    previous = id;

    const spotValue = collateralValue(exposure.collateralAmount, exposure.spotPrice);
    const stressValue = collateralValue(
      exposure.collateralAmount,
      stressedPrice(
        exposure.spotPrice,
        scenario,
        exposure.liquidityScoreBps,
        exposure.oracleConfidenceBps,
      ),
    );
    const effectiveDebt = mulDivUp(exposure.debt, BPS + scenario.debtGrowthBps, BPS);
    const requirement = mulDivUp(effectiveDebt, exposure.liquidationRatioBps, BPS);
    const recoverable = mulDiv(stressValue, BPS - exposure.liquidationPenaltyBps, BPS);

    return {
      collateralId: exposure.collateralId,
      spotValue,
      stressedValue: stressValue,
      effectiveDebt,
      liquidationRequirement: requirement,
      shortfall: requirement > stressValue ? requirement - stressValue : 0n,
      debtShareBps: 0n,
      collateralShareBps: 0n,
      ceilingUtilizationBps: ratioBps(effectiveDebt, exposure.debtCeiling),
      liquidationPrice: liquidationPrice(
        exposure.collateralAmount,
        effectiveDebt,
        exposure.liquidationRatioBps,
      ),
      capitalAtRisk: effectiveDebt > recoverable ? effectiveDebt - recoverable : 0n,
    } satisfies CollateralRisk;
  });

  const sum = (selector: (risk: CollateralRisk) => bigint): bigint =>
    collaterals.reduce((total, risk) => total + selector(risk), 0n);
  const totalSpotValue = sum((risk) => risk.spotValue);
  const totalStressedValue = sum((risk) => risk.stressedValue);
  const totalEffectiveDebt = sum((risk) => risk.effectiveDebt);
  const totalLiquidationRequirement = sum((risk) => risk.liquidationRequirement);
  const totalShortfall = sum((risk) => risk.shortfall);
  const totalDebtCeiling = exposures.reduce((total, exposure) => total + exposure.debtCeiling, 0n);
  const weightedRatioNumerator = exposures.reduce(
    (total, exposure, index) =>
      total + (collaterals[index]?.effectiveDebt ?? 0n) * exposure.liquidationRatioBps,
    0n,
  );

  let debtHhi = 0n;
  let collateralHhi = 0n;
  let largestDebtShare = 0n;
  for (const risk of collaterals) {
    risk.debtShareBps =
      totalEffectiveDebt === 0n ? 0n : ratioBps(risk.effectiveDebt, totalEffectiveDebt);
    risk.collateralShareBps = totalSpotValue === 0n ? 0n : ratioBps(risk.spotValue, totalSpotValue);
    debtHhi += mulDiv(risk.debtShareBps, risk.debtShareBps, BPS);
    collateralHhi += mulDiv(risk.collateralShareBps, risk.collateralShareBps, BPS);
    if (risk.debtShareBps > largestDebtShare) largestDebtShare = risk.debtShareBps;
  }

  const coverage =
    totalEffectiveDebt === 0n
      ? (1n << 256n) - 1n
      : ratioBps(totalStressedValue, totalEffectiveDebt);
  const utilization = ratioBps(totalEffectiveDebt, totalDebtCeiling);
  const weightedRatio =
    totalEffectiveDebt === 0n ? 0n : weightedRatioNumerator / totalEffectiveDebt;
  let score =
    totalLiquidationRequirement === 0n ? 0n : ratioBps(totalShortfall, totalLiquidationRequirement);
  score += excess(debtHhi, limits.maxDebtHhiBps);
  score += excess(collateralHhi, limits.maxCollateralHhiBps);
  score += excess(largestDebtShare, limits.maxSingleDebtShareBps);
  score += coverage === (1n << 256n) - 1n ? 0n : excess(limits.minStressedCoverageBps, coverage);
  score += excess(utilization, limits.maxDebtCeilingUtilizationBps);
  if (score > BPS) score = BPS;

  return {
    collaterals,
    portfolio: {
      totalSpotValue,
      totalStressedValue,
      totalEffectiveDebt,
      totalDebtCeiling,
      totalLiquidationRequirement,
      totalShortfall,
      stressedCoverageBps: coverage,
      weightedLiquidationRatioBps: weightedRatio,
      debtCeilingUtilizationBps: utilization,
      debtConcentrationHhiBps: debtHhi,
      collateralConcentrationHhiBps: collateralHhi,
      largestDebtShareBps: largestDebtShare,
      riskScoreBps: score,
      withinLimits:
        totalShortfall === 0n &&
        largestDebtShare <= limits.maxSingleDebtShareBps &&
        debtHhi <= limits.maxDebtHhiBps &&
        collateralHhi <= limits.maxCollateralHhiBps &&
        coverage >= limits.minStressedCoverageBps &&
        utilization <= limits.maxDebtCeilingUtilizationBps,
    },
  };
}

function excess(value: bigint, limit: bigint): bigint {
  return value > limit ? value - limit : 0n;
}

function assertScenario(scenario: StressScenario): void {
  assertBps(scenario.priceShockBps, "priceShockBps");
  assertBps(scenario.liquidityHaircutBps, "liquidityHaircutBps");
  assertBps(scenario.oracleDeviationBps, "oracleDeviationBps");
  assertBps(scenario.debtGrowthBps, "debtGrowthBps");
  assertBps(scenario.auctionSlippageBps, "auctionSlippageBps");
}

function assertLimits(limits: RiskLimits): void {
  assertBps(limits.maxSingleDebtShareBps, "maxSingleDebtShareBps");
  assertBps(limits.maxDebtHhiBps, "maxDebtHhiBps");
  assertBps(limits.maxCollateralHhiBps, "maxCollateralHhiBps");
  assertBps(limits.maxDebtCeilingUtilizationBps, "maxDebtCeilingUtilizationBps");
  if (limits.minStressedCoverageBps < BPS || limits.minStressedCoverageBps > 50_000n) {
    throw new RangeError("minStressedCoverageBps is outside the supported range");
  }
}

function assertExposure(exposure: CollateralExposure): void {
  if (!/^0x[0-9a-fA-F]{64}$/.test(exposure.collateralId)) {
    throw new TypeError("collateralId must be bytes32");
  }
  if (exposure.spotPrice <= 0n || exposure.debtCeiling <= 0n) {
    throw new RangeError("price and debt ceiling must be positive");
  }
  if (exposure.liquidationRatioBps < BPS) {
    throw new RangeError("liquidation ratio must be at least 100%");
  }
  assertBps(exposure.liquidationPenaltyBps, "liquidationPenaltyBps");
  assertBps(exposure.liquidityScoreBps, "liquidityScoreBps");
  assertBps(exposure.oracleConfidenceBps, "oracleConfidenceBps");
}

export function serializeBigInts(value: unknown): string {
  return JSON.stringify(value, (_key, candidate: unknown) =>
    typeof candidate === "bigint" ? candidate.toString() : candidate,
  );
}

export class BastionClient {
  readonly protocol: Address;
  readonly reader: ContractReader;

  constructor(protocol: Address, reader: ContractReader) {
    if (!/^0x[0-9a-fA-F]{40}$/.test(protocol)) throw new TypeError("invalid protocol address");
    this.protocol = protocol;
    this.reader = reader;
  }

  async vault(vaultId: bigint): Promise<Vault> {
    assertUnsigned(vaultId, "vaultId");
    return this.reader.readContract<Vault>({
      address: this.protocol,
      abi: protocolAbi,
      functionName: "vault",
      args: [vaultId],
    });
  }

  async vaultView(vaultId: bigint): Promise<VaultView> {
    assertUnsigned(vaultId, "vaultId");
    return this.reader.readContract<VaultView>({
      address: this.protocol,
      abi: protocolAbi,
      functionName: "vaultView",
      args: [vaultId],
    });
  }

  async collateralConfig(collateralToken: Address): Promise<CollateralConfig> {
    return this.reader.readContract<CollateralConfig>({
      address: this.protocol,
      abi: protocolAbi,
      functionName: "collateralConfig",
      args: [collateralToken],
    });
  }

  async modules(): Promise<ModuleAddresses> {
    return this.reader.readContract<ModuleAddresses>({
      address: this.protocol,
      abi: protocolAbi,
      functionName: "moduleAddresses",
    });
  }

  async systemSnapshot(): Promise<SystemSnapshot> {
    const modules = await this.modules();
    return this.reader.readContract<SystemSnapshot>({
      address: modules.accountingEngine,
      abi: accountingAbi,
      functionName: "snapshot",
    });
  }

  async vaultIdsOf(owner: Address): Promise<readonly bigint[]> {
    const modules = await this.modules();
    return this.reader.readContract<readonly bigint[]>({
      address: modules.vaultLedger,
      abi: ledgerAbi,
      functionName: "vaultsOf",
      args: [owner],
    });
  }
}
