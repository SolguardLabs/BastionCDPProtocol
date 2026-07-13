# Política de seguridad

BastionCDPProtocol protege vaults colateralizados, emisión de bUSD, stability
fees, liquidaciones, subastas de collateral y recapitalización.

## Modelo de seguridad

El protocolo separa privilegios por rol:

- administrador: gestión de roles y parámetros globales;
- risk manager: configuración de collateral, fees, límites y duración de
  auctions;
- auctioneer: apertura y mantenimiento de subastas;
- protocolo: operaciones internas entre módulos;
- minter/burner: emisión y quema controlada de tokens.

## Invariantes esperadas

- Un vault activo con deuda debe permanecer por encima del liquidation ratio.
- La deuda emitida debe respetar el debt ceiling del collateral.
- Las liquidaciones deben transferir el collateral al auction house.
- Las auctions deben quemar bUSD recuperado antes de emitir o liberar valor.
- Los oráculos deben entregar precios dentro de la ventana de frescura
  configurada.
- Los módulos de accounting deben reflejar deuda emitida, repagada, fees, bad
  debt y recuperación.

## Validación local

```bash
forge fmt --check
forge build --deny warnings
FOUNDRY_PROFILE=ci forge test --deny warnings
```

La configuración de GitHub Actions ejecuta `scripts/ci.sh` sobre cada push, pull
request o ejecución manual.

## Alcance de revisión

Incluye:

- contratos en `src/`;
- tests públicos en `tests/`;
- scripts de despliegue en `script/`;
- scripts de CI local en `scripts/`;
- configuración de Foundry y GitHub Actions.

No incluye:

- integraciones con oráculos externos;
- automatización de keeper off-chain;
- gestión de claves;
- interfaces externas no mantenidas en este repositorio.

## Reporte responsable

Los reportes deben incluir:

- impacto económico;
- precondiciones;
- secuencia mínima de verificación;
- contratos y funciones afectadas;
- propuesta de mitigación;
- tests recomendados.

No incluyas claves privadas, credenciales ni datos de terceros.
