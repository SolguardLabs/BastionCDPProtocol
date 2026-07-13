// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract StabilityFeeController is BastionAccessControl {
    using FixedPointMath for uint256;

    error InvalidRate();
    error InvalidIndex();

    uint256 public constant MIN_INDEX = BastionTypes.RAY;
    uint256 public constant MAX_ANNUAL_RATE_BPS = 5000;

    uint256 public currentIndex;
    uint256 public annualRateBps;
    uint64 public lastAccrued;

    event StabilityFeeAccrued(uint256 previousIndex, uint256 newIndex, uint256 elapsed);
    event StabilityRateUpdated(uint256 previousRateBps, uint256 newRateBps);
    event FeeIndexReset(uint256 index);

    constructor(
        address initialOwner,
        uint256 initialRateBps
    ) BastionAccessControl(initialOwner) {
        if (initialRateBps > MAX_ANNUAL_RATE_BPS) revert InvalidRate();
        currentIndex = BastionTypes.RAY;
        annualRateBps = initialRateBps;
        lastAccrued = uint64(block.timestamp);
    }

    function accrue() external onlyRole(BastionRoles.PROTOCOL_ROLE) returns (uint256) {
        return _accrue();
    }

    function poke() external returns (uint256) {
        return _accrue();
    }

    function setAnnualRate(
        uint256 newRateBps
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        if (newRateBps > MAX_ANNUAL_RATE_BPS) revert InvalidRate();
        _accrue();
        uint256 previous = annualRateBps;
        annualRateBps = newRateBps;
        emit StabilityRateUpdated(previous, newRateBps);
    }

    function setIndexForMigration(
        uint256 index
    ) external onlyRole(BastionRoles.DEFAULT_ADMIN_ROLE) {
        if (index < MIN_INDEX) revert InvalidIndex();
        currentIndex = index;
        lastAccrued = uint64(block.timestamp);
        emit FeeIndexReset(index);
    }

    function previewIndex() public view returns (uint256) {
        uint256 elapsed = block.timestamp - uint256(lastAccrued);
        return FixedPointMath.accrueLinear(currentIndex, annualRateBps, elapsed);
    }

    function feeSnapshot() external view returns (BastionTypes.FeeSnapshot memory) {
        return BastionTypes.FeeSnapshot({
            index: previewIndex(),
            annualRateBps: annualRateBps,
            lastAccrued: lastAccrued,
            timestamp: uint64(block.timestamp)
        });
    }

    function pendingFee(
        uint256 debt,
        uint256 vaultIndex
    ) external view returns (uint256) {
        return FixedPointMath.accruedFromIndex(debt, vaultIndex, previewIndex());
    }

    function _accrue() internal returns (uint256) {
        uint256 previous = currentIndex;
        uint256 elapsed = block.timestamp - uint256(lastAccrued);
        uint256 next = FixedPointMath.accrueLinear(previous, annualRateBps, elapsed);

        currentIndex = next;
        lastAccrued = uint64(block.timestamp);

        if (next != previous || elapsed != 0) {
            emit StabilityFeeAccrued(previous, next, elapsed);
        }

        return next;
    }
}
