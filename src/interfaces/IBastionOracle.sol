// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBastionOracle {
    function latestPrice(
        address asset
    ) external view returns (uint256 price, uint256 updatedAt);
    function isPriceFresh(
        address asset,
        uint256 maxAge
    ) external view returns (bool);
}
