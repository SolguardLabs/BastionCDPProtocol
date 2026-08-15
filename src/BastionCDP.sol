// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "./access/BastionAccessControl.sol";
import { CollateralAuctionHouse } from "./auctions/CollateralAuctionHouse.sol";
import { DebtAuctionHouse } from "./auctions/DebtAuctionHouse.sol";
import { AccountingEngine } from "./core/AccountingEngine.sol";
import { BastionReentrancyGuard } from "./core/BastionReentrancyGuard.sol";
import { RiskEngine } from "./core/RiskEngine.sol";
import { StabilityFeeController } from "./core/StabilityFeeController.sol";
import { VaultLedger } from "./core/VaultLedger.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { BastionDebtToken } from "./tokens/BastionDebtToken.sol";
import { BastionProtocolShare } from "./tokens/BastionProtocolShare.sol";
import { BastionTypes } from "./types/BastionTypes.sol";

contract BastionCDP is BastionAccessControl, BastionReentrancyGuard {
    using SafeTransferLib for address;
    using FixedPointMath for uint256;

    error ProtocolPaused();
    error VaultNotOwned();
    error InvalidAmount();
    error InvalidRecipient();
    error VaultHasDebt();
    error VaultHealthy();
    error CollateralNotSupported();
    error InvalidModule();

    BastionDebtToken public immutable debtToken;
    BastionProtocolShare public immutable protocolShare;
    VaultLedger public immutable ledger;
    AccountingEngine public immutable accounting;
    StabilityFeeController public immutable feeController;
    RiskEngine public immutable riskEngine;
    CollateralAuctionHouse public immutable collateralAuctionHouse;
    DebtAuctionHouse public immutable debtAuctionHouse;

    bool public paused;

    event PauseUpdated(bool paused);
    event CollateralConfigured(address indexed collateral, address indexed oracle, uint256 minDebt);
    event VaultOpened(uint256 indexed vaultId, address indexed owner, address indexed collateral);
    event CollateralDeposited(uint256 indexed vaultId, address indexed owner, uint256 amount);
    event CollateralWithdrawn(
        uint256 indexed vaultId, address indexed owner, address indexed recipient, uint256 amount
    );
    event DebtMinted(
        uint256 indexed vaultId, address indexed owner, uint256 amount, uint256 newDebt
    );
    event DebtRepaid(
        uint256 indexed vaultId, address indexed payer, uint256 amount, uint256 newDebt
    );
    event VaultFeesSettled(uint256 indexed vaultId, uint256 feesAccrued, uint256 feeIndex);
    event VaultLiquidated(
        uint256 indexed vaultId,
        address indexed liquidator,
        uint256 indexed auctionId,
        uint256 debt,
        uint256 collateral
    );
    event DebtAuctionOpened(uint256 indexed auctionId, uint256 debtToCover, uint256 shareLot);

    modifier whenNotPaused() {
        if (paused) revert ProtocolPaused();
        _;
    }

    constructor(
        address admin,
        BastionDebtToken debtToken_,
        BastionProtocolShare protocolShare_,
        VaultLedger ledger_,
        AccountingEngine accounting_,
        StabilityFeeController feeController_,
        RiskEngine riskEngine_,
        CollateralAuctionHouse collateralAuctionHouse_,
        DebtAuctionHouse debtAuctionHouse_
    ) BastionAccessControl(admin) {
        if (
            address(debtToken_) == address(0) || address(protocolShare_) == address(0)
                || address(ledger_) == address(0) || address(accounting_) == address(0)
                || address(feeController_) == address(0) || address(riskEngine_) == address(0)
                || address(collateralAuctionHouse_) == address(0)
                || address(debtAuctionHouse_) == address(0)
        ) revert InvalidModule();

        _grantRole(BastionRoles.RISK_MANAGER_ROLE, admin);
        _grantRole(BastionRoles.AUCTIONEER_ROLE, admin);
        _grantRole(BastionRoles.PAUSER_ROLE, admin);

        debtToken = debtToken_;
        protocolShare = protocolShare_;
        ledger = ledger_;
        accounting = accounting_;
        feeController = feeController_;
        riskEngine = riskEngine_;
        collateralAuctionHouse = collateralAuctionHouse_;
        debtAuctionHouse = debtAuctionHouse_;
    }

    function setPaused(
        bool paused_
    ) external onlyRole(BastionRoles.PAUSER_ROLE) {
        paused = paused_;
        emit PauseUpdated(paused_);
    }

    function setStabilityRate(
        uint256 annualRateBps
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        feeController.setAnnualRate(annualRateBps);
    }

    function setCollateralAuctionDuration(
        uint64 duration
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        collateralAuctionHouse.setDefaultDuration(duration);
    }

    function setDebtAuctionParameters(
        uint64 duration,
        uint256 minIncreaseBps
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        debtAuctionHouse.setParameters(duration, minIncreaseBps);
    }

    function configureCollateral(
        address collateralToken,
        address oracle,
        string calldata symbol,
        uint256 debtCeiling,
        uint256 minDebt,
        uint256 liquidationRatioBps,
        uint256 liquidationPenaltyBps,
        uint256 maxPriceAge,
        uint256 auctionDiscountBps,
        uint256 closeFactorBps,
        bool enabled
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        BastionTypes.CollateralConfig memory config = BastionTypes.CollateralConfig({
            enabled: enabled,
            token: collateralToken,
            oracle: oracle,
            debtCeiling: debtCeiling,
            minDebt: minDebt,
            liquidationRatioBps: liquidationRatioBps,
            liquidationPenaltyBps: liquidationPenaltyBps,
            maxPriceAge: maxPriceAge,
            auctionDiscountBps: auctionDiscountBps,
            closeFactorBps: closeFactorBps,
            symbol: symbol
        });

        riskEngine.validateConfig(config);

        if (ledger.isCollateralListed(collateralToken)) {
            ledger.updateCollateral(config);
        } else {
            ledger.listCollateral(config);
        }

        emit CollateralConfigured(collateralToken, oracle, minDebt);
    }

    function openVault(
        address collateralToken
    ) external whenNotPaused returns (uint256 vaultId) {
        uint256 index = feeController.accrue();
        vaultId = ledger.createVault(msg.sender, collateralToken, index);
        BastionTypes.CollateralConfig memory config = ledger.collateralConfig(collateralToken);
        accounting.recordVaultOpened(msg.sender, config.token, vaultId);
        emit VaultOpened(vaultId, msg.sender, collateralToken);
    }

    function depositCollateral(
        uint256 vaultId,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();

        BastionTypes.Vault memory position = _requireOwnedActive(vaultId, msg.sender);
        address(position.collateralToken).safeTransferFrom(msg.sender, address(this), amount);
        ledger.increaseCollateral(vaultId, amount);

        emit CollateralDeposited(vaultId, msg.sender, amount);
    }

    function mintDebt(
        uint256 vaultId,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();

        (BastionTypes.Vault memory position,) = _settleVaultFees(vaultId);
        if (position.owner != msg.sender) revert VaultNotOwned();
        if (position.status != BastionTypes.VaultStatus.Active) revert CollateralNotSupported();

        BastionTypes.CollateralConfig memory config =
            ledger.collateralConfig(position.collateralToken);

        riskEngine.validateMint(
            config,
            position.collateralAmount,
            position.debt,
            amount,
            accounting.normalizedDebtByCollateral(position.collateralToken)
        );

        ledger.increaseDebt(vaultId, amount);
        debtToken.mint(msg.sender, amount);
        accounting.recordDebtIssued(position.collateralToken, amount);

        emit DebtMinted(vaultId, msg.sender, amount, position.debt + amount);
    }

    function repayDebt(
        uint256 vaultId,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();

        BastionTypes.Vault memory position = _requireOwnedActive(vaultId, msg.sender);
        if (position.debt == 0) revert InvalidAmount();

        BastionTypes.CollateralConfig memory config =
            ledger.collateralConfig(position.collateralToken);
        uint256 index = feeController.accrue();
        uint256 burnAmount = FixedPointMath.min(amount, position.debt);
        uint256 debtAfterPrincipal = position.debt - burnAmount;

        debtToken.burnFrom(msg.sender, burnAmount);

        if (debtAfterPrincipal == 0) {
            ledger.setDebt(vaultId, 0);
            ledger.setFeeIndex(vaultId, index);
            accounting.recordDebtRepaid(position.collateralToken, burnAmount);
            emit DebtRepaid(vaultId, msg.sender, burnAmount, 0);
            return;
        }

        if (debtAfterPrincipal < config.minDebt) {
            ledger.setDebt(vaultId, 0);
            ledger.setFeeIndex(vaultId, index);
            accounting.recordDebtRepaid(position.collateralToken, position.debt);
            emit DebtRepaid(vaultId, msg.sender, burnAmount, 0);
            return;
        }

        ledger.setDebt(vaultId, debtAfterPrincipal);

        uint256 fees = FixedPointMath.accruedFromIndex(debtAfterPrincipal, position.feeIndex, index);
        uint256 finalDebt = debtAfterPrincipal;

        if (fees != 0) {
            finalDebt += fees;
            ledger.setDebt(vaultId, finalDebt);
            accounting.recordFeesAccrued(position.collateralToken, fees);
            emit VaultFeesSettled(vaultId, fees, index);
        }

        ledger.setFeeIndex(vaultId, index);
        riskEngine.validateDebtState(config, finalDebt);

        if (!riskEngine.isHealthy(config, position.collateralAmount, finalDebt)) {
            revert RiskEngine.VaultWouldBeUnsafe();
        }

        accounting.recordDebtRepaid(position.collateralToken, burnAmount);
        emit DebtRepaid(vaultId, msg.sender, burnAmount, finalDebt);
    }

    function withdrawCollateral(
        uint256 vaultId,
        uint256 amount,
        address recipient
    ) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (recipient == address(0)) revert InvalidRecipient();

        (BastionTypes.Vault memory position,) = _settleVaultFees(vaultId);
        if (position.owner != msg.sender) revert VaultNotOwned();
        if (position.status != BastionTypes.VaultStatus.Active) revert CollateralNotSupported();

        BastionTypes.CollateralConfig memory config =
            ledger.collateralConfig(position.collateralToken);
        riskEngine.validateWithdrawal(config, position.collateralAmount, amount, position.debt);

        ledger.decreaseCollateral(vaultId, amount);
        address(position.collateralToken).safeTransfer(recipient, amount);

        uint256 remainingCollateral = position.collateralAmount - amount;
        if (remainingCollateral == 0 && position.debt == 0) {
            ledger.closeVault(vaultId, feeController.currentIndex());
            accounting.recordVaultClosed(position.owner, position.collateralToken, vaultId);
        }

        emit CollateralWithdrawn(vaultId, msg.sender, recipient, amount);
    }

    function liquidate(
        uint256 vaultId
    ) external whenNotPaused nonReentrant returns (uint256 auctionId) {
        (BastionTypes.Vault memory position,) = _settleVaultFees(vaultId);
        BastionTypes.CollateralConfig memory config =
            ledger.collateralConfig(position.collateralToken);

        if (riskEngine.isHealthy(config, position.collateralAmount, position.debt)) {
            revert VaultHealthy();
        }
        if (position.debt == 0 || position.collateralAmount == 0) revert InvalidAmount();

        uint256 debtToRecover = riskEngine.liquidationDebt(config, position.debt);
        uint256 collateralAmount = position.collateralAmount;

        ledger.setStatus(vaultId, BastionTypes.VaultStatus.Liquidating);
        ledger.setCollateralAmount(vaultId, 0);
        ledger.setDebt(vaultId, 0);
        accounting.recordVaultLiquidating(position.collateralToken, vaultId);
        accounting.recordBadDebt(position.collateralToken, position.debt);

        address(position.collateralToken)
            .safeTransfer(address(collateralAuctionHouse), collateralAmount);

        auctionId = collateralAuctionHouse.startAuction(
            position.collateralToken,
            position.owner,
            collateralAmount,
            debtToRecover,
            config.auctionDiscountBps
        );

        emit VaultLiquidated(vaultId, msg.sender, auctionId, position.debt, collateralAmount);
    }

    function openDebtAuction(
        uint256 debtToCover,
        uint256 shareLot
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) returns (uint256 auctionId) {
        auctionId = debtAuctionHouse.startAuction(debtToCover, shareLot);
        emit DebtAuctionOpened(auctionId, debtToCover, shareLot);
    }

    function vault(
        uint256 vaultId
    ) external view returns (BastionTypes.Vault memory) {
        return ledger.getVault(vaultId);
    }

    function collateralConfig(
        address collateralToken
    ) external view returns (BastionTypes.CollateralConfig memory) {
        return ledger.collateralConfig(collateralToken);
    }

    function previewFees(
        uint256 vaultId
    ) public view returns (uint256) {
        BastionTypes.Vault memory data = ledger.getVault(vaultId);
        return feeController.pendingFee(data.debt, data.feeIndex);
    }

    function vaultView(
        uint256 vaultId
    ) external view returns (BastionTypes.VaultView memory view_) {
        BastionTypes.Vault memory data = ledger.getVault(vaultId);
        BastionTypes.CollateralConfig memory config = ledger.collateralConfig(data.collateralToken);
        uint256 price = riskEngine.priceOf(config);
        uint256 value = FixedPointMath.collateralValue(data.collateralAmount, price);
        uint256 pendingFees = previewFees(vaultId);
        uint256 debtWithFees = data.debt + pendingFees;
        bool healthy = riskEngine.isHealthy(config, data.collateralAmount, debtWithFees);

        view_ = BastionTypes.VaultView({
            vault: data,
            collateral: config,
            collateralPrice: price,
            collateralValue: value,
            liquidationDebt: riskEngine.liquidationDebt(config, debtWithFees),
            pendingFees: pendingFees,
            healthy: healthy
        });
    }

    function moduleAddresses()
        external
        view
        returns (
            address debt,
            address share,
            address vaultLedger,
            address accountingEngine,
            address fees,
            address collateralAuction,
            address debtAuction
        )
    {
        return (
            address(debtToken),
            address(protocolShare),
            address(ledger),
            address(accounting),
            address(feeController),
            address(collateralAuctionHouse),
            address(debtAuctionHouse)
        );
    }

    function _settleVaultFees(
        uint256 vaultId
    ) internal returns (BastionTypes.Vault memory data, uint256 fees) {
        data = ledger.getVault(vaultId);
        uint256 index = feeController.accrue();

        fees = FixedPointMath.accruedFromIndex(data.debt, data.feeIndex, index);

        if (fees != 0) {
            data.debt += fees;
            ledger.setDebt(vaultId, data.debt);
            accounting.recordFeesAccrued(data.collateralToken, fees);
            emit VaultFeesSettled(vaultId, fees, index);
        }

        if (data.feeIndex != index) {
            ledger.setFeeIndex(vaultId, index);
            data.feeIndex = index;
        }
    }

    function _requireOwnedActive(
        uint256 vaultId,
        address account
    ) internal view returns (BastionTypes.Vault memory data) {
        data = ledger.getVault(vaultId);
        if (data.owner != account) revert VaultNotOwned();
        if (data.status != BastionTypes.VaultStatus.Active) revert CollateralNotSupported();
    }
}
