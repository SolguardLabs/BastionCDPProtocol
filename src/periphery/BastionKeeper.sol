// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionCDP } from "../BastionCDP.sol";
import { CollateralAuctionHouse } from "../auctions/CollateralAuctionHouse.sol";
import { DebtAuctionHouse } from "../auctions/DebtAuctionHouse.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract BastionKeeper {
    struct LiquidationResult {
        uint256 vaultId;
        uint256 auctionId;
        bool executed;
        bytes errorData;
    }

    struct AuctionSettleResult {
        uint256 auctionId;
        bool executed;
        bytes errorData;
    }

    event BatchLiquidationChecked(uint256 indexed vaultId, bool executed, uint256 auctionId);
    event BatchCollateralAuctionSettled(uint256 indexed auctionId, bool executed);
    event BatchDebtAuctionSettled(uint256 indexed auctionId, bool executed);

    function liquidateMany(
        BastionCDP protocol,
        uint256[] calldata vaultIds
    ) external returns (LiquidationResult[] memory results) {
        results = new LiquidationResult[](vaultIds.length);

        for (uint256 i = 0; i < vaultIds.length; i++) {
            uint256 vaultId = vaultIds[i];

            try protocol.liquidate(vaultId) returns (uint256 auctionId) {
                results[i] = LiquidationResult({
                    vaultId: vaultId, auctionId: auctionId, executed: true, errorData: ""
                });
                emit BatchLiquidationChecked(vaultId, true, auctionId);
            } catch (bytes memory reason) {
                results[i] = LiquidationResult({
                    vaultId: vaultId, auctionId: 0, executed: false, errorData: reason
                });
                emit BatchLiquidationChecked(vaultId, false, 0);
            }
        }
    }

    function settleExpiredCollateralAuctions(
        CollateralAuctionHouse auctionHouse,
        uint256[] calldata auctionIds
    ) external returns (AuctionSettleResult[] memory results) {
        results = new AuctionSettleResult[](auctionIds.length);

        for (uint256 i = 0; i < auctionIds.length; i++) {
            uint256 auctionId = auctionIds[i];

            try auctionHouse.settleExpired(auctionId) {
                results[i] =
                    AuctionSettleResult({ auctionId: auctionId, executed: true, errorData: "" });
                emit BatchCollateralAuctionSettled(auctionId, true);
            } catch (bytes memory reason) {
                results[i] = AuctionSettleResult({
                    auctionId: auctionId, executed: false, errorData: reason
                });
                emit BatchCollateralAuctionSettled(auctionId, false);
            }
        }
    }

    function settleDebtAuctions(
        DebtAuctionHouse auctionHouse,
        uint256[] calldata auctionIds
    ) external returns (AuctionSettleResult[] memory results) {
        results = new AuctionSettleResult[](auctionIds.length);

        for (uint256 i = 0; i < auctionIds.length; i++) {
            uint256 auctionId = auctionIds[i];

            try auctionHouse.settle(auctionId) {
                results[i] =
                    AuctionSettleResult({ auctionId: auctionId, executed: true, errorData: "" });
                emit BatchDebtAuctionSettled(auctionId, true);
            } catch (bytes memory reason) {
                results[i] = AuctionSettleResult({
                    auctionId: auctionId, executed: false, errorData: reason
                });
                emit BatchDebtAuctionSettled(auctionId, false);
            }
        }
    }

    function unhealthyVaults(
        BastionCDP protocol,
        uint256[] calldata vaultIds
    ) external view returns (uint256[] memory unhealthyIds, uint256 count) {
        unhealthyIds = new uint256[](vaultIds.length);

        for (uint256 i = 0; i < vaultIds.length; i++) {
            try protocol.vaultView(vaultIds[i]) returns (BastionTypes.VaultView memory view_) {
                if (!view_.healthy && view_.vault.status == BastionTypes.VaultStatus.Active) {
                    unhealthyIds[count] = vaultIds[i];
                    count += 1;
                }
            } catch { }
        }
    }

    function liveCollateralAuctions(
        CollateralAuctionHouse auctionHouse,
        uint256 fromId,
        uint256 toId
    ) external view returns (uint256[] memory liveIds, uint256 count) {
        require(toId >= fromId, "BASTION_BAD_RANGE");
        liveIds = new uint256[](toId - fromId + 1);

        for (uint256 id = fromId; id <= toId; id++) {
            try auctionHouse.auction(id) returns (BastionTypes.CollateralAuction memory auction) {
                if (auction.status == BastionTypes.AuctionStatus.Live) {
                    liveIds[count] = id;
                    count += 1;
                }
            } catch { }
        }
    }

    function liveDebtAuctions(
        DebtAuctionHouse auctionHouse,
        uint256 fromId,
        uint256 toId
    ) external view returns (uint256[] memory liveIds, uint256 count) {
        require(toId >= fromId, "BASTION_BAD_RANGE");
        liveIds = new uint256[](toId - fromId + 1);

        for (uint256 id = fromId; id <= toId; id++) {
            try auctionHouse.auction(id) returns (BastionTypes.DebtAuction memory auction) {
                if (auction.status == BastionTypes.AuctionStatus.Live) {
                    liveIds[count] = id;
                    count += 1;
                }
            } catch { }
        }
    }
}
