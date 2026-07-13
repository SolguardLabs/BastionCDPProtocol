// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionTypes } from "../types/BastionTypes.sol";

library FixedPointMath {
    error DivisionByZero();
    error ExponentTooLarge();

    function min(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function absDiff(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function ceilDiv(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        if (a == 0) return 0;
        return ((a - 1) / b) + 1;
    }

    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        if (denominator == 0) revert DivisionByZero();

        unchecked {
            uint256 prod0;
            uint256 prod1;

            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                return prod0 / denominator;
            }

            require(denominator > prod1);

            uint256 remainder;

            assembly {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = denominator & (~denominator + 1);

            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }

            prod0 |= prod1 * twos;

            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            z = prod0 * inverse;
        }
    }

    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256) {
        uint256 z = mulDiv(x, y, denominator);
        if (mulmod(x, y, denominator) > 0) {
            z += 1;
        }
        return z;
    }

    function mulWad(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, y, BastionTypes.WAD);
    }

    function mulWadUp(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, y, BastionTypes.WAD);
    }

    function divWad(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, BastionTypes.WAD, y);
    }

    function divWadUp(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, BastionTypes.WAD, y);
    }

    function mulRay(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, y, BastionTypes.RAY);
    }

    function mulRayUp(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, y, BastionTypes.RAY);
    }

    function divRay(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, BastionTypes.RAY, y);
    }

    function bp(
        uint256 amount,
        uint256 bps
    ) internal pure returns (uint256) {
        return mulDiv(amount, bps, BastionTypes.BPS);
    }

    function bpUp(
        uint256 amount,
        uint256 bps
    ) internal pure returns (uint256) {
        return mulDivUp(amount, bps, BastionTypes.BPS);
    }

    function clamp(
        uint256 value,
        uint256 lower,
        uint256 upper
    ) internal pure returns (uint256) {
        if (value < lower) return lower;
        if (value > upper) return upper;
        return value;
    }

    function ratioBps(
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (uint256) {
        if (denominator == 0) revert DivisionByZero();
        return mulDiv(numerator, BastionTypes.BPS, denominator);
    }

    function wadToRay(
        uint256 wad
    ) internal pure returns (uint256) {
        return wad * 1e9;
    }

    function rayToWad(
        uint256 ray
    ) internal pure returns (uint256) {
        return ray / 1e9;
    }

    function accrueLinear(
        uint256 index,
        uint256 annualRateBps,
        uint256 elapsed
    ) internal pure returns (uint256) {
        if (elapsed == 0 || annualRateBps == 0) return index;
        uint256 increment =
            mulDiv(index, annualRateBps * elapsed, BastionTypes.BPS * BastionTypes.YEAR);
        return index + increment;
    }

    function accruedFromIndex(
        uint256 debt,
        uint256 fromIndex,
        uint256 toIndex
    ) internal pure returns (uint256) {
        if (debt == 0 || toIndex <= fromIndex) return 0;
        uint256 indexedDebt = mulDivUp(debt, toIndex, fromIndex);
        return indexedDebt - debt;
    }

    function collateralValue(
        uint256 amount,
        uint256 price
    ) internal pure returns (uint256) {
        return mulWad(amount, price);
    }

    function liquidationDebt(
        uint256 debt,
        uint256 penaltyBps
    ) internal pure returns (uint256) {
        return debt + bpUp(debt, penaltyBps);
    }

    function isRatioAtLeast(
        uint256 numerator,
        uint256 denominator,
        uint256 minRatioBps
    ) internal pure returns (bool) {
        if (denominator == 0) return true;
        return ratioBps(numerator, denominator) >= minRatioBps;
    }

    function boundedSub(
        uint256 value,
        uint256 subtrahend
    ) internal pure returns (uint256) {
        return subtrahend >= value ? 0 : value - subtrahend;
    }

    function average(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return (a & b) + ((a ^ b) >> 1);
    }

    function weightedAverage(
        uint256 a,
        uint256 weightA,
        uint256 b,
        uint256 weightB
    ) internal pure returns (uint256) {
        uint256 totalWeight = weightA + weightB;
        if (totalWeight == 0) revert DivisionByZero();
        return mulDiv(a, weightA, totalWeight) + mulDiv(b, weightB, totalWeight);
    }

    function rpow(
        uint256 x,
        uint256 n,
        uint256 scalar
    ) internal pure returns (uint256 z) {
        if (scalar == 0) revert DivisionByZero();
        if (n > 10_000_000) revert ExponentTooLarge();

        assembly {
            switch x
            case 0 {
                switch n
                case 0 {
                    z := scalar
                }
                default {
                    z := 0
                }
            }
            default {
                switch mod(n, 2)
                case 0 {
                    z := scalar
                }
                default {
                    z := x
                }
                let half := div(scalar, 2)
                for {
                    n := div(n, 2)
                } n {
                    n := div(n, 2)
                } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) {
                        revert(0, 0)
                    }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }
                    x := div(xxRound, scalar)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                            revert(0, 0)
                        }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }
                        z := div(zxRound, scalar)
                    }
                }
            }
        }
    }
}
