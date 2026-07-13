// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { IBastionOracle } from "../interfaces/IBastionOracle.sol";

contract MedianPriceOracle is IBastionOracle, BastionAccessControl {
    error InvalidPrice();
    error InvalidAsset();
    error PriceTooOld(address asset, uint256 updatedAt, uint256 maxAge);

    struct PriceRound {
        uint256 roundId;
        uint256 price;
        uint64 updatedAt;
        uint64 minValidUntil;
        address reporter;
    }

    uint256 public constant MIN_PRICE = 1e6;
    uint256 public constant MAX_PRICE = 1_000_000_000e18;

    mapping(address asset => PriceRound round) private _rounds;
    mapping(address asset => uint256 deviationBps) public maxDeviationBps;

    event PricePosted(
        address indexed asset,
        uint256 indexed roundId,
        uint256 price,
        uint256 updatedAt,
        address indexed reporter
    );
    event DeviationLimitUpdated(address indexed asset, uint256 maxDeviationBps);

    constructor(
        address initialOwner
    ) BastionAccessControl(initialOwner) { }

    function setDeviationLimit(
        address asset,
        uint256 deviationLimitBps
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        if (asset == address(0)) revert InvalidAsset();
        require(deviationLimitBps <= 5000, "BASTION_DEVIATION_TOO_HIGH");
        maxDeviationBps[asset] = deviationLimitBps;
        emit DeviationLimitUpdated(asset, deviationLimitBps);
    }

    function postPrice(
        address asset,
        uint256 price
    ) external onlyRole(BastionRoles.ORACLE_POSTER_ROLE) {
        _postPrice(asset, price, 0);
    }

    function postGuardedPrice(
        address asset,
        uint256 price,
        uint64 minValidUntil
    ) external onlyRole(BastionRoles.ORACLE_POSTER_ROLE) {
        _postPrice(asset, price, minValidUntil);
    }

    function latestPrice(
        address asset
    ) external view override returns (uint256 price, uint256 updatedAt) {
        PriceRound memory round = _rounds[asset];
        return (round.price, round.updatedAt);
    }

    function latestRound(
        address asset
    ) external view returns (PriceRound memory) {
        return _rounds[asset];
    }

    function isPriceFresh(
        address asset,
        uint256 maxAge
    ) external view override returns (bool) {
        PriceRound memory round = _rounds[asset];
        if (round.price == 0) return false;
        // forge-lint: disable-next-line(block-timestamp)
        if (round.minValidUntil != 0 && block.timestamp <= round.minValidUntil) return true;
        // forge-lint: disable-next-line(block-timestamp)
        return block.timestamp <= uint256(round.updatedAt) + maxAge;
    }

    function requireFreshPrice(
        address asset,
        uint256 maxAge
    ) external view returns (uint256) {
        PriceRound memory round = _rounds[asset];
        // forge-lint: disable-next-line(block-timestamp)
        if (round.price == 0 || block.timestamp > uint256(round.updatedAt) + maxAge) {
            revert PriceTooOld(asset, round.updatedAt, maxAge);
        }
        return round.price;
    }

    function _postPrice(
        address asset,
        uint256 price,
        uint64 minValidUntil
    ) internal {
        if (asset == address(0)) revert InvalidAsset();
        if (price < MIN_PRICE || price > MAX_PRICE) revert InvalidPrice();

        PriceRound memory previous = _rounds[asset];
        uint256 deviationLimit = maxDeviationBps[asset];

        if (previous.price != 0 && deviationLimit != 0) {
            uint256 upper = previous.price + ((previous.price * deviationLimit) / 10_000);
            uint256 lower = previous.price - ((previous.price * deviationLimit) / 10_000);
            require(price >= lower && price <= upper, "BASTION_PRICE_DEVIATION");
        }

        uint256 roundId = previous.roundId + 1;
        _rounds[asset] = PriceRound({
            roundId: roundId,
            price: price,
            updatedAt: uint64(block.timestamp),
            minValidUntil: minValidUntil,
            reporter: msg.sender
        });

        emit PricePosted(asset, roundId, price, block.timestamp, msg.sender);
    }
}
