// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library BastionTypes {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant YEAR = 365 days;

    enum VaultStatus {
        None,
        Active,
        Liquidating,
        Closed
    }

    enum AuctionStatus {
        None,
        Live,
        Settled,
        Cancelled
    }

    struct CollateralConfig {
        bool enabled;
        address token;
        address oracle;
        uint256 debtCeiling;
        uint256 minDebt;
        uint256 liquidationRatioBps;
        uint256 liquidationPenaltyBps;
        uint256 maxPriceAge;
        uint256 auctionDiscountBps;
        uint256 closeFactorBps;
        string symbol;
    }

    struct Vault {
        uint256 id;
        address owner;
        address collateralToken;
        uint256 collateralAmount;
        uint256 debt;
        uint256 feeIndex;
        uint64 openedAt;
        uint64 updatedAt;
        VaultStatus status;
    }

    struct VaultView {
        Vault vault;
        CollateralConfig collateral;
        uint256 collateralPrice;
        uint256 collateralValue;
        uint256 liquidationDebt;
        uint256 pendingFees;
        bool healthy;
    }

    struct CollateralAuction {
        uint256 id;
        address collateralToken;
        address vaultOwner;
        uint256 collateralRemaining;
        uint256 debtRemaining;
        uint256 initialCollateral;
        uint256 initialDebt;
        uint256 minBidBps;
        uint64 startedAt;
        uint64 expiresAt;
        AuctionStatus status;
    }

    struct DebtAuction {
        uint256 id;
        address initiator;
        address highestBidder;
        uint256 debtToCover;
        uint256 shareLot;
        uint256 highestBid;
        uint64 startedAt;
        uint64 expiresAt;
        AuctionStatus status;
    }

    struct FeeSnapshot {
        uint256 index;
        uint256 annualRateBps;
        uint64 lastAccrued;
        uint64 timestamp;
    }

    struct SystemSnapshot {
        uint256 totalNormalizedDebt;
        uint256 totalIssuedDebt;
        uint256 totalRepaidDebt;
        uint256 totalFeesAccrued;
        uint256 totalBadDebt;
        uint256 totalRecoveredDebt;
        uint256 activeVaults;
        uint256 liquidatingVaults;
        uint256 closedVaults;
    }
}
