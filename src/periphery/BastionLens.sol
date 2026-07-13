// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionCDP } from "../BastionCDP.sol";
import { CollateralAuctionHouse } from "../auctions/CollateralAuctionHouse.sol";
import { DebtAuctionHouse } from "../auctions/DebtAuctionHouse.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract BastionLens {
    using FixedPointMath for uint256;

    function vaultView(
        BastionCDP protocol,
        uint256 vaultId
    ) external view returns (BastionTypes.VaultView memory) {
        return protocol.vaultView(vaultId);
    }

    function vaultsOf(
        BastionCDP protocol,
        address owner
    ) external view returns (uint256[] memory) {
        return protocol.ledger().vaultsOf(owner);
    }

    function collateralAuction(
        CollateralAuctionHouse auctionHouse,
        uint256 auctionId
    )
        external
        view
        returns (BastionTypes.CollateralAuction memory auction, uint256 nextFullPurchaseCost)
    {
        auction = auctionHouse.auction(auctionId);
        nextFullPurchaseCost = auction.debtRemaining;
    }

    function debtAuction(
        DebtAuctionHouse auctionHouse,
        uint256 auctionId
    ) external view returns (BastionTypes.DebtAuction memory auction, uint256 minimumNextBid) {
        auction = auctionHouse.auction(auctionId);
        minimumNextBid = auctionHouse.minimumNextBid(auctionId);
    }

    function liquidationBufferBps(
        BastionTypes.VaultView memory view_
    ) external pure returns (uint256) {
        if (view_.vault.debt == 0) return type(uint256).max;
        uint256 ratio = FixedPointMath.ratioBps(view_.collateralValue, view_.vault.debt);
        if (ratio <= view_.collateral.liquidationRatioBps) return 0;
        return ratio - view_.collateral.liquidationRatioBps;
    }

    function debtCapacityRemaining(
        BastionCDP protocol,
        address collateralToken
    ) external view returns (uint256) {
        BastionTypes.CollateralConfig memory config = protocol.collateralConfig(collateralToken);
        uint256 used = protocol.accounting().normalizedDebtByCollateral(collateralToken);
        return config.debtCeiling > used ? config.debtCeiling - used : 0;
    }
}
