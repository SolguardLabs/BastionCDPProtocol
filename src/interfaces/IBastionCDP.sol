// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { AccountingEngine } from "../core/AccountingEngine.sol";
import { StabilityFeeController } from "../core/StabilityFeeController.sol";
import { VaultLedger } from "../core/VaultLedger.sol";
import { BastionDebtToken } from "../tokens/BastionDebtToken.sol";
import { BastionProtocolShare } from "../tokens/BastionProtocolShare.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

interface IBastionCDP {
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

    function debtToken() external view returns (BastionDebtToken);
    function protocolShare() external view returns (BastionProtocolShare);
    function ledger() external view returns (VaultLedger);
    function accounting() external view returns (AccountingEngine);
    function feeController() external view returns (StabilityFeeController);
    function paused() external view returns (bool);

    function setPaused(
        bool paused_
    ) external;
    function setStabilityRate(
        uint256 annualRateBps
    ) external;
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
    ) external;
    function openVault(
        address collateralToken
    ) external returns (uint256 vaultId);
    function depositCollateral(
        uint256 vaultId,
        uint256 amount
    ) external;
    function mintDebt(
        uint256 vaultId,
        uint256 amount
    ) external;
    function repayDebt(
        uint256 vaultId,
        uint256 amount
    ) external;
    function withdrawCollateral(
        uint256 vaultId,
        uint256 amount,
        address recipient
    ) external;
    function liquidate(
        uint256 vaultId
    ) external returns (uint256 auctionId);
    function openDebtAuction(
        uint256 debtToCover,
        uint256 shareLot
    ) external returns (uint256 auctionId);
    function vault(
        uint256 vaultId
    ) external view returns (BastionTypes.Vault memory);
    function collateralConfig(
        address collateralToken
    ) external view returns (BastionTypes.CollateralConfig memory);
    function previewFees(
        uint256 vaultId
    ) external view returns (uint256);
    function vaultView(
        uint256 vaultId
    ) external view returns (BastionTypes.VaultView memory);
}
