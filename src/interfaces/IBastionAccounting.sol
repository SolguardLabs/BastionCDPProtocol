// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBastionAccounting {
    function recordDebtRecovered(
        address collateral,
        uint256 amount
    ) external;
}
