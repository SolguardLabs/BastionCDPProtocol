# Bastion CDP Protocol

![banner](./assets/banner.png)

BastionCDPProtocol es un sistema CDP en Solidity para emitir deuda sintética
contra collateral volátil. El protocolo modela vaults colateralizados, accrual
de stability fees, liquidaciones con subasta de collateral y debt auctions para
recapitalización.

## Componentes

- `BastionCDP`: fachada principal para vaults, mint, repay, withdraw,
  liquidate y apertura de debt auctions.
- `VaultLedger`: registro de posiciones, collateral, deuda y estado de vaults.
- `StabilityFeeController`: índice global de stability fees con accrual lineal.
- `RiskEngine`: validación de collateralización, debt ceilings y liquidación.
- `CollateralAuctionHouse`: subastas de collateral liquidado pagadas en bUSD.
- `DebtAuctionHouse`: subastas de recapitalización a cambio de shares BRS.
- `AccountingEngine`: métricas de deuda emitida, repagada, fees, bad debt y
  recuperación.
- `MedianPriceOracle`: oracle administrado para precios de collateral.

## Flujo operativo

1. El risk manager lista un collateral con oracle, debt ceiling, mínimo de deuda,
   liquidation ratio y parámetros de auction.
2. Un usuario abre un vault, deposita collateral y mintea bUSD si la posición
   queda por encima del ratio requerido.
3. El vault acumula stability fees mediante el índice global.
4. El usuario puede repagar deuda y retirar collateral siempre que el vault
   mantenga solvencia.
5. Si el precio cae y la posición incumple el ratio de liquidación, cualquier
   keeper puede iniciar la liquidación.
6. El collateral liquidado se vende por bUSD en `CollateralAuctionHouse`.
7. Si el sistema necesita recapitalización, `DebtAuctionHouse` permite vender
   shares BRS a cambio de bUSD.

## Seguridad y controles

- Roles separados para administración, riesgo, auctions, protocolo y emisión de
  tokens.
- Debt ceilings por collateral.
- Oracle con ventana de frescura configurada.
- Stability fee global acumulada por índice.
- Auctions separadas para collateral y recapitalización.
- Accounting de deuda emitida, repagada, fees, bad debt y recuperación.

Consulta [SECURITY.md](./SECURITY.md) para el alcance de revisión y las
invariantes esperadas.

## Requisitos

- Foundry `forge`.
- Solidity `0.8.26`.

## Comandos

```bash
forge build --deny warnings
forge test --deny warnings
bash scripts/tests.sh
bash scripts/ci.sh
```

## Tests

La suite pública cubre:

- creación de vault;
- depósito de collateral;
- mint de deuda;
- repay parcial y total;
- withdraw tras limpiar deuda;
- liquidación por caída de precio;
- compra de collateral liquidado;
- settlement de debt auction.

## Estructura

```text
src/
  access/
  auctions/
  core/
  interfaces/
  libraries/
  oracle/
  periphery/
  tokens/
  types/
tests/
  helpers/
  integration/
  unit/
script/
scripts/
```
