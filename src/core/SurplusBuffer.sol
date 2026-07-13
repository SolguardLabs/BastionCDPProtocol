// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";

contract SurplusBuffer is BastionAccessControl {
    using SafeTransferLib for address;

    error InsufficientBuffer();
    error InvalidAsset();
    error InvalidRecipient();

    struct AssetBuffer {
        uint256 expectedBalance;
        uint256 reservedForAuctions;
        uint256 releasedToTreasury;
        uint64 lastUpdated;
    }

    mapping(address asset => AssetBuffer buffer) private _buffers;
    address[] private _assets;
    mapping(address asset => bool listed) private _listed;

    event AssetRegistered(address indexed asset);
    event SurplusDeposited(address indexed asset, address indexed from, uint256 amount);
    event AuctionReserveIncreased(address indexed asset, uint256 amount);
    event AuctionReserveReleased(address indexed asset, uint256 amount);
    event TreasuryWithdrawal(address indexed asset, address indexed recipient, uint256 amount);

    constructor(
        address initialOwner
    ) BastionAccessControl(initialOwner) { }

    function registerAsset(
        address asset
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        if (asset == address(0)) revert InvalidAsset();
        if (_listed[asset]) return;
        _listed[asset] = true;
        _assets.push(asset);
        emit AssetRegistered(asset);
    }

    function deposit(
        address asset,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        _requireAsset(asset);
        address(asset).safeTransferFrom(msg.sender, address(this), amount);

        AssetBuffer storage buffer = _buffers[asset];
        buffer.expectedBalance += amount;
        buffer.lastUpdated = uint64(block.timestamp);

        emit SurplusDeposited(asset, msg.sender, amount);
    }

    function accountSurplus(
        address asset,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        _requireAsset(asset);

        AssetBuffer storage buffer = _buffers[asset];
        buffer.expectedBalance += amount;
        buffer.lastUpdated = uint64(block.timestamp);

        emit SurplusDeposited(asset, msg.sender, amount);
    }

    function reserveForAuction(
        address asset,
        uint256 amount
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) {
        _requireAsset(asset);

        AssetBuffer storage buffer = _buffers[asset];
        uint256 freeBalance = available(asset);
        if (amount > freeBalance) revert InsufficientBuffer();

        buffer.reservedForAuctions += amount;
        buffer.lastUpdated = uint64(block.timestamp);

        emit AuctionReserveIncreased(asset, amount);
    }

    function releaseAuctionReserve(
        address asset,
        uint256 amount
    ) external onlyRole(BastionRoles.AUCTIONEER_ROLE) {
        _requireAsset(asset);

        AssetBuffer storage buffer = _buffers[asset];
        if (amount > buffer.reservedForAuctions) revert InsufficientBuffer();

        buffer.reservedForAuctions -= amount;
        buffer.lastUpdated = uint64(block.timestamp);

        emit AuctionReserveReleased(asset, amount);
    }

    function withdrawToTreasury(
        address asset,
        address recipient,
        uint256 amount
    ) external onlyRole(BastionRoles.DEFAULT_ADMIN_ROLE) {
        _requireAsset(asset);
        if (recipient == address(0)) revert InvalidRecipient();

        AssetBuffer storage buffer = _buffers[asset];
        uint256 freeBalance = available(asset);
        if (amount > freeBalance) revert InsufficientBuffer();

        buffer.expectedBalance -= amount;
        buffer.releasedToTreasury += amount;
        buffer.lastUpdated = uint64(block.timestamp);

        address(asset).safeTransfer(recipient, amount);

        emit TreasuryWithdrawal(asset, recipient, amount);
    }

    function reconcile(
        address asset
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) returns (uint256 drift) {
        _requireAsset(asset);

        AssetBuffer storage buffer = _buffers[asset];
        uint256 actual = IERC20Minimal(asset).balanceOf(address(this));
        uint256 expected = buffer.expectedBalance;

        if (actual >= expected) {
            drift = actual - expected;
            buffer.expectedBalance = actual;
        } else {
            drift = expected - actual;
            buffer.expectedBalance = actual;
            if (buffer.reservedForAuctions > actual) {
                buffer.reservedForAuctions = actual;
            }
        }

        buffer.lastUpdated = uint64(block.timestamp);
    }

    function available(
        address asset
    ) public view returns (uint256) {
        AssetBuffer memory buffer = _buffers[asset];
        if (buffer.expectedBalance <= buffer.reservedForAuctions) return 0;
        return buffer.expectedBalance - buffer.reservedForAuctions;
    }

    function bufferOf(
        address asset
    ) external view returns (AssetBuffer memory) {
        _requireAsset(asset);
        return _buffers[asset];
    }

    function assetCount() external view returns (uint256) {
        return _assets.length;
    }

    function assetAt(
        uint256 index
    ) external view returns (address) {
        return _assets[index];
    }

    function _requireAsset(
        address asset
    ) internal view {
        if (!_listed[asset]) revert InvalidAsset();
    }
}
