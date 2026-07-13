// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionTypes } from "../../src/types/BastionTypes.sol";
import { BastionTestBase } from "../helpers/BastionTestBase.sol";

contract LiquidationAndAuctionTest is BastionTestBase {
    function testLiquidationStartsCollateralAuction() public {
        uint256 vaultId = openDepositAndMint(alice, 10e18, 10_000e18);
        setOraclePrice(1000e18);

        vm.prank(keeper);
        uint256 auctionId = protocol.liquidate(vaultId);

        BastionTypes.Vault memory data = protocol.vault(vaultId);
        BastionTypes.CollateralAuction memory auction = collateralAuction.auction(auctionId);

        assertEq(uint256(data.status), uint256(BastionTypes.VaultStatus.Liquidating));
        assertEq(data.collateralAmount, 0);
        assertEq(data.debt, 0);
        assertEq(auction.collateralRemaining, 10e18);
        assertEq(auction.debtRemaining, 11_300e18);
        assertEq(auction.vaultOwner, alice);
    }

    function testCollateralAuctionAllowsDebtPurchase() public {
        uint256 aliceVault = openDepositAndMint(alice, 10e18, 10_000e18);
        openDepositAndMint(bob, 20e18, 5000e18);

        setOraclePrice(1000e18);

        vm.prank(keeper);
        uint256 auctionId = protocol.liquidate(aliceVault);

        uint256 bobCollateralBefore = collateral.balanceOf(bob);
        uint256 bobDebtBefore = debt.balanceOf(bob);
        uint256 quote = collateralAuction.quoteCollateral(auctionId, 1000e18);

        vm.prank(bob);
        (uint256 collateralOut, uint256 debtPaid) =
            collateralAuction.buyCollateral(auctionId, 1000e18, bob);

        BastionTypes.CollateralAuction memory auction = collateralAuction.auction(auctionId);

        assertEq(collateralOut, quote);
        assertEq(debtPaid, 1000e18);
        assertEq(collateral.balanceOf(bob), bobCollateralBefore + quote);
        assertEq(debt.balanceOf(bob), bobDebtBefore - 1000e18);
        assertEq(auction.debtRemaining, 10_300e18);
        assertEq(protocol.accounting().recoveredDebtByCollateral(address(collateral)), 1000e18);
    }

    function testDebtAuctionSettlementIssuesRecapitalizationShares() public {
        openDepositAndMint(bob, 20e18, 5000e18);

        vm.prank(admin);
        uint256 auctionId = protocol.openDebtAuction(1000e18, 100e18);

        vm.startPrank(bob);
        debt.approve(address(debtAuction), 1000e18);
        debtAuction.bid(auctionId, 800e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours + 1);

        debtAuction.settle(auctionId);

        BastionTypes.DebtAuction memory auction = debtAuction.auction(auctionId);

        assertEq(uint256(auction.status), uint256(BastionTypes.AuctionStatus.Settled));
        assertEq(auction.highestBidder, bob);
        assertEq(share.balanceOf(bob), 100e18);
        assertEq(debt.balanceOf(bob), 4200e18);
    }
}
