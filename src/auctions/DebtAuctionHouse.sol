// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { BastionReentrancyGuard } from "../core/BastionReentrancyGuard.sol";
import { IBastionAccounting } from "../interfaces/IBastionAccounting.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { BastionDebtToken } from "../tokens/BastionDebtToken.sol";
import { BastionProtocolShare } from "../tokens/BastionProtocolShare.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract DebtAuctionHouse is BastionAccessControl, BastionReentrancyGuard {
    using SafeTransferLib for address;

    error AuctionNotLive();
    error AuctionNotExpired();
    error InvalidAuction();
    error InvalidBid();
    error InvalidRecipient();

    uint256 public nextAuctionId = 1;
    uint64 public defaultDuration = 4 hours;
    uint256 public minBidIncreaseBps = 300;

    BastionDebtToken public immutable debtToken;
    BastionProtocolShare public immutable protocolShare;
    IBastionAccounting public accounting;

    mapping(uint256 auctionId => BastionTypes.DebtAuction auction) private _auctions;

    event AccountingUpdated(address indexed accounting);
    event DebtAuctionParametersUpdated(uint64 duration, uint256 minBidIncreaseBps);
    event DebtAuctionStarted(
        uint256 indexed auctionId, address indexed initiator, uint256 debtToCover, uint256 shareLot
    );
    event DebtBidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount);
    event DebtAuctionSettled(
        uint256 indexed auctionId, address indexed winner, uint256 winningBid, uint256 shareLot
    );
    event DebtAuctionCancelled(uint256 indexed auctionId);

    constructor(
        address initialOwner,
        BastionDebtToken debtToken_,
        BastionProtocolShare protocolShare_
    ) BastionAccessControl(initialOwner) {
        debtToken = debtToken_;
        protocolShare = protocolShare_;
    }

    function setAccounting(
        address accounting_
    ) external onlyRole(BastionRoles.DEFAULT_ADMIN_ROLE) {
        accounting = IBastionAccounting(accounting_);
        emit AccountingUpdated(accounting_);
    }

    function setParameters(
        uint64 duration,
        uint256 minIncreaseBps
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        require(duration >= 30 minutes && duration <= 14 days, "BASTION_BAD_DURATION");
        require(minIncreaseBps <= 2000, "BASTION_BAD_INCREMENT");
        defaultDuration = duration;
        minBidIncreaseBps = minIncreaseBps;
        emit DebtAuctionParametersUpdated(duration, minIncreaseBps);
    }

    function startAuction(
        uint256 debtToCover,
        uint256 shareLot
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) returns (uint256 auctionId) {
        if (debtToCover == 0 || shareLot == 0) revert InvalidAuction();

        auctionId = nextAuctionId++;
        _auctions[auctionId] = BastionTypes.DebtAuction({
            id: auctionId,
            initiator: msg.sender,
            highestBidder: address(0),
            debtToCover: debtToCover,
            shareLot: shareLot,
            highestBid: 0,
            startedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + defaultDuration),
            status: BastionTypes.AuctionStatus.Live
        });

        emit DebtAuctionStarted(auctionId, msg.sender, debtToCover, shareLot);
    }

    function bid(
        uint256 auctionId,
        uint256 amount
    ) external nonReentrant {
        BastionTypes.DebtAuction storage sale = _requireLive(auctionId);
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > sale.expiresAt) revert AuctionNotLive();
        if (amount == 0 || amount > sale.debtToCover) revert InvalidBid();

        uint256 minBid = minimumNextBid(auctionId);
        if (amount < minBid) revert InvalidBid();

        address previousBidder = sale.highestBidder;
        uint256 previousBid = sale.highestBid;

        address(debtToken).safeTransferFrom(msg.sender, address(this), amount);

        sale.highestBidder = msg.sender;
        sale.highestBid = amount;

        if (previousBidder != address(0)) {
            address(debtToken).safeTransfer(previousBidder, previousBid);
        }

        emit DebtBidPlaced(auctionId, msg.sender, amount);
    }

    function settle(
        uint256 auctionId
    ) external nonReentrant {
        BastionTypes.DebtAuction storage sale = _requireLive(auctionId);
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp <= sale.expiresAt) revert AuctionNotExpired();
        if (sale.highestBidder == address(0)) revert InvalidBid();

        sale.status = BastionTypes.AuctionStatus.Settled;

        debtToken.burn(address(this), sale.highestBid);
        protocolShare.mint(sale.highestBidder, sale.shareLot);
        accounting.recordDebtRecovered(address(debtToken), sale.highestBid);

        emit DebtAuctionSettled(auctionId, sale.highestBidder, sale.highestBid, sale.shareLot);
    }

    function cancel(
        uint256 auctionId,
        address refundRecipient
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) nonReentrant {
        if (refundRecipient == address(0)) revert InvalidRecipient();

        BastionTypes.DebtAuction storage sale = _requireLive(auctionId);
        sale.status = BastionTypes.AuctionStatus.Cancelled;

        if (sale.highestBid != 0) {
            address(debtToken).safeTransfer(refundRecipient, sale.highestBid);
        }

        emit DebtAuctionCancelled(auctionId);
    }

    function minimumNextBid(
        uint256 auctionId
    ) public view returns (uint256) {
        BastionTypes.DebtAuction memory sale = _auctions[auctionId];
        if (sale.id == 0) revert InvalidAuction();

        if (sale.highestBid == 0) {
            return sale.debtToCover / 2;
        }

        uint256 increment = (sale.highestBid * minBidIncreaseBps) / 10_000;
        return sale.highestBid + increment;
    }

    function auction(
        uint256 auctionId
    ) external view returns (BastionTypes.DebtAuction memory) {
        BastionTypes.DebtAuction memory data = _auctions[auctionId];
        if (data.id == 0) revert InvalidAuction();
        return data;
    }

    function _requireLive(
        uint256 auctionId
    ) internal view returns (BastionTypes.DebtAuction storage sale) {
        sale = _auctions[auctionId];
        if (sale.id == 0) revert InvalidAuction();
        if (sale.status != BastionTypes.AuctionStatus.Live) revert AuctionNotLive();
    }
}
