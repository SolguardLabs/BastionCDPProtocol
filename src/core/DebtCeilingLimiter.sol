// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";

contract DebtCeilingLimiter is BastionAccessControl {
    error InvalidWindow();
    error LimitExceeded();
    error AssetNotConfigured();

    struct LimitConfig {
        bool enabled;
        uint128 maxMintPerWindow;
        uint64 windowSize;
    }

    struct LimitState {
        uint128 mintedInWindow;
        uint64 windowStart;
    }

    mapping(address asset => LimitConfig config) private _configs;
    mapping(address asset => LimitState state) private _states;
    address[] private _assets;
    mapping(address asset => bool listed) private _listed;

    event LimitConfigured(
        address indexed asset, uint256 maxMintPerWindow, uint64 windowSize, bool enabled
    );
    event LimitConsumed(address indexed asset, uint256 amount, uint256 mintedInWindow);
    event LimitWindowReset(address indexed asset, uint64 windowStart);

    constructor(
        address initialOwner
    ) BastionAccessControl(initialOwner) { }

    function configure(
        address asset,
        uint128 maxMintPerWindow,
        uint64 windowSize,
        bool enabled
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        if (asset == address(0) || windowSize == 0) revert InvalidWindow();

        if (!_listed[asset]) {
            _listed[asset] = true;
            _assets.push(asset);
        }

        _configs[asset] = LimitConfig({
            enabled: enabled, maxMintPerWindow: maxMintPerWindow, windowSize: windowSize
        });

        if (_states[asset].windowStart == 0) {
            _states[asset].windowStart = uint64(block.timestamp);
        }

        emit LimitConfigured(asset, maxMintPerWindow, windowSize, enabled);
    }

    function consume(
        address asset,
        uint128 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        LimitConfig memory config = _configs[asset];
        if (!_listed[asset]) revert AssetNotConfigured();
        if (!config.enabled) return;

        LimitState storage state = _states[asset];
        _rollWindowIfNeeded(asset, config, state);

        uint256 nextMinted = uint256(state.mintedInWindow) + amount;
        if (nextMinted > config.maxMintPerWindow) revert LimitExceeded();

        // forge-lint: disable-next-line(unsafe-typecast)
        state.mintedInWindow = uint128(nextMinted);

        emit LimitConsumed(asset, amount, nextMinted);
    }

    function reset(
        address asset
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        if (!_listed[asset]) revert AssetNotConfigured();

        LimitState storage state = _states[asset];
        state.mintedInWindow = 0;
        state.windowStart = uint64(block.timestamp);

        emit LimitWindowReset(asset, state.windowStart);
    }

    function available(
        address asset
    ) external view returns (uint256) {
        LimitConfig memory config = _configs[asset];
        LimitState memory state = _states[asset];

        if (!_listed[asset]) revert AssetNotConfigured();
        if (!config.enabled) return type(uint256).max;
        if (_windowExpired(config, state)) return config.maxMintPerWindow;
        if (state.mintedInWindow >= config.maxMintPerWindow) return 0;

        return config.maxMintPerWindow - state.mintedInWindow;
    }

    function previewConsume(
        address asset,
        uint128 amount
    ) external view returns (bool allowed, uint256 remaining) {
        LimitConfig memory config = _configs[asset];
        LimitState memory state = _states[asset];

        if (!_listed[asset]) revert AssetNotConfigured();
        if (!config.enabled) return (true, type(uint256).max);

        uint256 minted = _windowExpired(config, state) ? 0 : state.mintedInWindow;
        uint256 nextMinted = minted + amount;

        if (nextMinted > config.maxMintPerWindow) {
            return (false, config.maxMintPerWindow > minted ? config.maxMintPerWindow - minted : 0);
        }

        return (true, config.maxMintPerWindow - nextMinted);
    }

    function configOf(
        address asset
    ) external view returns (LimitConfig memory) {
        if (!_listed[asset]) revert AssetNotConfigured();
        return _configs[asset];
    }

    function stateOf(
        address asset
    ) external view returns (LimitState memory) {
        if (!_listed[asset]) revert AssetNotConfigured();
        return _states[asset];
    }

    function configured(
        address asset
    ) external view returns (bool) {
        return _listed[asset];
    }

    function windowEndsAt(
        address asset
    ) external view returns (uint256) {
        if (!_listed[asset]) revert AssetNotConfigured();
        return uint256(_states[asset].windowStart) + _configs[asset].windowSize;
    }

    function assetCount() external view returns (uint256) {
        return _assets.length;
    }

    function assetAt(
        uint256 index
    ) external view returns (address) {
        return _assets[index];
    }

    function _rollWindowIfNeeded(
        address asset,
        LimitConfig memory config,
        LimitState storage state
    ) internal {
        if (_windowExpired(config, state)) {
            state.mintedInWindow = 0;
            state.windowStart = uint64(block.timestamp);
            emit LimitWindowReset(asset, state.windowStart);
        }
    }

    function _windowExpired(
        LimitConfig memory config,
        LimitState memory state
    ) internal view returns (bool) {
        // forge-lint: disable-next-line(block-timestamp)
        return block.timestamp >= uint256(state.windowStart) + config.windowSize;
    }
}
