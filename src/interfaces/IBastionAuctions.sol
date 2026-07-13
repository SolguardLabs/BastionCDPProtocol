// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionTypes } from "../types/BastionTypes.sol";

interface IBastionCollateralAuctionHouse {
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

    function startAuction(
        address collateralToken,
        address vaultOwner,
        uint256 collateralAmount,
        uint256 debtToRecover,
        uint256 minBidBps
    ) external returns (uint256 auctionId);
    function buyCollateral(
        uint256 auctionId,
        uint256 debtAmount,
        address recipient
    ) external returns (uint256 collateralOut, uint256 debtPaid);
    function settleExpired(
        uint256 auctionId
    ) external;
    function cancelAuction(
        uint256 auctionId,
        address recipient
    ) external;
    function quoteCollateral(
        uint256 auctionId,
        uint256 debtAmount
    ) external view returns (uint256);
    function auction(
        uint256 auctionId
    ) external view returns (BastionTypes.CollateralAuction memory);
}

interface IBastionDebtAuctionHouse {
    event DebtAuctionStarted(
        uint256 indexed auctionId, address indexed initiator, uint256 debtToCover, uint256 shareLot
    );
    event DebtBidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount);
    event DebtAuctionSettled(
        uint256 indexed auctionId, address indexed winner, uint256 winningBid, uint256 shareLot
    );
    event DebtAuctionCancelled(uint256 indexed auctionId);

    function startAuction(
        uint256 debtToCover,
        uint256 shareLot
    ) external returns (uint256 auctionId);
    function bid(
        uint256 auctionId,
        uint256 amount
    ) external;
    function settle(
        uint256 auctionId
    ) external;
    function cancel(
        uint256 auctionId,
        address refundRecipient
    ) external;
    function minimumNextBid(
        uint256 auctionId
    ) external view returns (uint256);
    function auction(
        uint256 auctionId
    ) external view returns (BastionTypes.DebtAuction memory);
}
