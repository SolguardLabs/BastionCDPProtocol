// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";

contract LiquidationQueue is BastionAccessControl {
    error QueueItemMissing();
    error QueueItemExists();
    error InvalidPriority();

    struct QueueItem {
        uint256 vaultId;
        address collateralToken;
        uint256 debt;
        uint256 collateralValue;
        uint256 priorityBps;
        uint64 addedAt;
        bool active;
    }

    uint256[] private _vaultIds;
    mapping(uint256 vaultId => QueueItem item) private _items;
    mapping(uint256 vaultId => uint256 indexPlusOne) private _indexes;

    event CandidateQueued(
        uint256 indexed vaultId, address indexed collateralToken, uint256 debt, uint256 priorityBps
    );
    event CandidateUpdated(uint256 indexed vaultId, uint256 debt, uint256 priorityBps);
    event CandidateRemoved(uint256 indexed vaultId);
    event QueueCleared(uint256 removed);

    constructor(
        address initialOwner
    ) BastionAccessControl(initialOwner) { }

    function enqueue(
        uint256 vaultId,
        address collateralToken,
        uint256 debt,
        uint256 collateralValue,
        uint256 priorityBps
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) {
        if (_indexes[vaultId] != 0) revert QueueItemExists();
        if (priorityBps > 100_000) revert InvalidPriority();

        _vaultIds.push(vaultId);
        _indexes[vaultId] = _vaultIds.length;
        _items[vaultId] = QueueItem({
            vaultId: vaultId,
            collateralToken: collateralToken,
            debt: debt,
            collateralValue: collateralValue,
            priorityBps: priorityBps,
            addedAt: uint64(block.timestamp),
            active: true
        });

        emit CandidateQueued(vaultId, collateralToken, debt, priorityBps);
    }

    function update(
        uint256 vaultId,
        uint256 debt,
        uint256 collateralValue,
        uint256 priorityBps
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) {
        if (_indexes[vaultId] == 0) revert QueueItemMissing();
        if (priorityBps > 100_000) revert InvalidPriority();

        QueueItem storage queued = _items[vaultId];
        queued.debt = debt;
        queued.collateralValue = collateralValue;
        queued.priorityBps = priorityBps;

        emit CandidateUpdated(vaultId, debt, priorityBps);
    }

    function remove(
        uint256 vaultId
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) {
        _remove(vaultId);
    }

    function popHighestPriority()
        external
        onlyRole(BastionRoles.AUCTIONEER_ROLE)
        returns (QueueItem memory queued)
    {
        uint256 bestIndex = _bestIndex();
        if (bestIndex == type(uint256).max) revert QueueItemMissing();

        uint256 vaultId = _vaultIds[bestIndex];
        queued = _items[vaultId];
        _remove(vaultId);
    }

    function peekHighestPriority() external view returns (QueueItem memory queued) {
        uint256 bestIndex = _bestIndex();
        if (bestIndex == type(uint256).max) revert QueueItemMissing();
        queued = _items[_vaultIds[bestIndex]];
    }

    function item(
        uint256 vaultId
    ) external view returns (QueueItem memory) {
        if (_indexes[vaultId] == 0) revert QueueItemMissing();
        return _items[vaultId];
    }

    function contains(
        uint256 vaultId
    ) external view returns (bool) {
        return _indexes[vaultId] != 0;
    }

    function count() external view returns (uint256) {
        return _vaultIds.length;
    }

    function vaultIdAt(
        uint256 index
    ) external view returns (uint256) {
        return _vaultIds[index];
    }

    function clear(
        uint256 maxItems
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) returns (uint256 removed) {
        while (_vaultIds.length != 0 && removed < maxItems) {
            uint256 vaultId = _vaultIds[_vaultIds.length - 1];
            _indexes[vaultId] = 0;
            delete _items[vaultId];
            _vaultIds.pop();
            removed += 1;
        }

        emit QueueCleared(removed);
    }

    function _remove(
        uint256 vaultId
    ) internal {
        uint256 indexPlusOne = _indexes[vaultId];
        if (indexPlusOne == 0) revert QueueItemMissing();

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = _vaultIds.length - 1;

        if (index != lastIndex) {
            uint256 movedVaultId = _vaultIds[lastIndex];
            _vaultIds[index] = movedVaultId;
            _indexes[movedVaultId] = index + 1;
        }

        _vaultIds.pop();
        _indexes[vaultId] = 0;
        delete _items[vaultId];

        emit CandidateRemoved(vaultId);
    }

    function _bestIndex() internal view returns (uint256 bestIndex) {
        bestIndex = type(uint256).max;
        uint256 bestPriority = 0;

        for (uint256 i = 0; i < _vaultIds.length; i++) {
            QueueItem memory current = _items[_vaultIds[i]];
            if (current.active && current.priorityBps >= bestPriority) {
                bestPriority = current.priorityBps;
                bestIndex = i;
            }
        }
    }
}
