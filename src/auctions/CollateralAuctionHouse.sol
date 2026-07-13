// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { BastionReentrancyGuard } from "../core/BastionReentrancyGuard.sol";
import { IBastionAccounting } from "../interfaces/IBastionAccounting.sol";
import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { BastionDebtToken } from "../tokens/BastionDebtToken.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract CollateralAuctionHouse is BastionAccessControl, BastionReentrancyGuard {
    using SafeTransferLib for address;
    using FixedPointMath for uint256;

    error AuctionNotLive();
    error AuctionExpired();
    error InvalidAuction();
    error InvalidBid();
    error InvalidRecipient();

    uint256 public nextAuctionId = 1;
    uint64 public defaultDuration = 2 hours;

    BastionDebtToken public immutable debtToken;
    IBastionAccounting public accounting;

    mapping(uint256 auctionId => BastionTypes.CollateralAuction auction) private _auctions;

    event AccountingUpdated(address indexed accounting);
    event AuctionDurationUpdated(uint64 duration);
    event CollateralAuctionStarted(
        uint256 indexed auctionId,
        address indexed collateralToken,
        address indexed vaultOwner,
        uint256 collateralAmount,
        uint256 debtToRecover
    );
    event CollateralPurchased(
        uint256 indexed auctionId,
        address indexed bidder,
        address indexed recipient,
        uint256 collateralAmount,
        uint256 debtPaid
    );
    event CollateralAuctionSettled(uint256 indexed auctionId, uint256 recoveredDebt);
    event CollateralAuctionCancelled(uint256 indexed auctionId);

    constructor(
        address initialOwner,
        BastionDebtToken debtToken_
    ) BastionAccessControl(initialOwner) {
        debtToken = debtToken_;
    }

    function setAccounting(
        address accounting_
    ) external onlyRole(BastionRoles.DEFAULT_ADMIN_ROLE) {
        accounting = IBastionAccounting(accounting_);
        emit AccountingUpdated(accounting_);
    }

    function setDefaultDuration(
        uint64 duration
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        require(duration >= 15 minutes && duration <= 7 days, "BASTION_BAD_DURATION");
        defaultDuration = duration;
        emit AuctionDurationUpdated(duration);
    }

    function startAuction(
        address collateralToken,
        address vaultOwner,
        uint256 collateralAmount,
        uint256 debtToRecover,
        uint256 minBidBps
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) returns (uint256 auctionId) {
        if (collateralToken == address(0)) revert InvalidAuction();
        if (vaultOwner == address(0)) revert InvalidAuction();
        if (collateralAmount == 0 || debtToRecover == 0) revert InvalidAuction();
        if (minBidBps > 10_000) revert InvalidBid();

        auctionId = nextAuctionId++;
        _auctions[auctionId] = BastionTypes.CollateralAuction({
            id: auctionId,
            collateralToken: collateralToken,
            vaultOwner: vaultOwner,
            collateralRemaining: collateralAmount,
            debtRemaining: debtToRecover,
            initialCollateral: collateralAmount,
            initialDebt: debtToRecover,
            minBidBps: minBidBps,
            startedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + defaultDuration),
            status: BastionTypes.AuctionStatus.Live
        });

        emit CollateralAuctionStarted(
            auctionId, collateralToken, vaultOwner, collateralAmount, debtToRecover
        );
    }

    function buyCollateral(
        uint256 auctionId,
        uint256 debtAmount,
        address recipient
    ) external nonReentrant returns (uint256 collateralOut, uint256 debtPaid) {
        if (recipient == address(0)) revert InvalidRecipient();

        BastionTypes.CollateralAuction storage sale = _requireLive(auctionId);
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > sale.expiresAt) revert AuctionExpired();
        if (debtAmount == 0) revert InvalidBid();

        debtPaid = FixedPointMath.min(debtAmount, sale.debtRemaining);
        collateralOut = quoteCollateral(auctionId, debtPaid);

        if (collateralOut == 0 || collateralOut > sale.collateralRemaining) revert InvalidBid();

        debtToken.burnFrom(msg.sender, debtPaid);
        address(sale.collateralToken).safeTransfer(recipient, collateralOut);

        sale.debtRemaining -= debtPaid;
        sale.collateralRemaining -= collateralOut;

        accounting.recordDebtRecovered(sale.collateralToken, debtPaid);

        emit CollateralPurchased(auctionId, msg.sender, recipient, collateralOut, debtPaid);

        if (sale.debtRemaining == 0 || sale.collateralRemaining == 0) {
            sale.status = BastionTypes.AuctionStatus.Settled;
            emit CollateralAuctionSettled(auctionId, sale.initialDebt - sale.debtRemaining);
        }
    }

    function settleExpired(
        uint256 auctionId
    ) external nonReentrant {
        BastionTypes.CollateralAuction storage sale = _requireLive(auctionId);
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp <= sale.expiresAt) revert AuctionNotLive();

        sale.status = BastionTypes.AuctionStatus.Settled;

        uint256 remainder = sale.collateralRemaining;
        sale.collateralRemaining = 0;

        if (remainder != 0) {
            address(sale.collateralToken).safeTransfer(sale.vaultOwner, remainder);
        }

        emit CollateralAuctionSettled(auctionId, sale.initialDebt - sale.debtRemaining);
    }

    function cancelAuction(
        uint256 auctionId,
        address recipient
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) nonReentrant {
        if (recipient == address(0)) revert InvalidRecipient();

        BastionTypes.CollateralAuction storage sale = _requireLive(auctionId);
        sale.status = BastionTypes.AuctionStatus.Cancelled;

        uint256 remainder = sale.collateralRemaining;
        sale.collateralRemaining = 0;

        if (remainder != 0) {
            address(sale.collateralToken).safeTransfer(recipient, remainder);
        }

        emit CollateralAuctionCancelled(auctionId);
    }

    function quoteCollateral(
        uint256 auctionId,
        uint256 debtAmount
    ) public view returns (uint256) {
        BastionTypes.CollateralAuction memory sale = _auctions[auctionId];
        if (sale.status != BastionTypes.AuctionStatus.Live) revert AuctionNotLive();
        if (debtAmount == 0) return 0;

        uint256 baseOut =
            FixedPointMath.mulDiv(debtAmount, sale.collateralRemaining, sale.debtRemaining);

        uint256 discountBoost = FixedPointMath.bp(baseOut, sale.minBidBps);
        uint256 withDiscount = baseOut + discountBoost;
        return FixedPointMath.min(withDiscount, sale.collateralRemaining);
    }

    function auction(
        uint256 auctionId
    ) external view returns (BastionTypes.CollateralAuction memory) {
        BastionTypes.CollateralAuction memory data = _auctions[auctionId];
        if (data.id == 0) revert InvalidAuction();
        return data;
    }

    function auctionStatus(
        uint256 auctionId
    ) external view returns (BastionTypes.AuctionStatus) {
        return _auctions[auctionId].status;
    }

    function liveDebt(
        uint256 auctionId
    ) external view returns (uint256) {
        return _auctions[auctionId].debtRemaining;
    }

    function liveCollateral(
        uint256 auctionId
    ) external view returns (uint256) {
        return _auctions[auctionId].collateralRemaining;
    }

    function _requireLive(
        uint256 auctionId
    ) internal view returns (BastionTypes.CollateralAuction storage sale) {
        sale = _auctions[auctionId];
        if (sale.id == 0) revert InvalidAuction();
        if (sale.status != BastionTypes.AuctionStatus.Live) revert AuctionNotLive();
    }
}
