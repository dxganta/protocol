// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.9;

import { Fix, FixLib, toFix as libToFix, toFixWithShift as libToFixWithShift, intToFix as libIntToFix, divFix as libDivFix, fixMin as libFixMin, fixMax as libFixMax } from "../Fixed.sol";

// Simple mock for Fixed library.
contract FixedCallerMock {
    function toFix(uint256 x) public pure returns (Fix) {
        return libToFix(x);
    }

    function toFixWithShift(uint256 x, int8 shiftLeft) public pure returns (Fix) {
        return libToFixWithShift(x, shiftLeft);
    }

    function intToFix(int256 x) public pure returns (Fix) {
        return libIntToFix(x);
    }

    function divFix(uint256 x, Fix y) public pure returns (Fix) {
        return libDivFix(x, y);
    }

    function fixMin(Fix x, Fix y) public pure returns (Fix) {
        return libFixMin(x, y);
    }

    function fixMax(Fix x, Fix y) public pure returns (Fix) {
        return libFixMax(x, y);
    }

    function toInt(Fix x) public pure returns (int192) {
        return FixLib.toInt(x);
    }

    function toUint(Fix x) public pure returns (uint192) {
        return FixLib.toUint(x);
    }

    function shiftLeft(Fix x, int8 shiftLeft) public pure returns (Fix) {
        return FixLib.shiftLeft(x, shiftLeft);
    }

    function round(Fix x) public pure returns (int192) {
        return FixLib.round(x);
    }

    function plus(Fix x, Fix y) public pure returns (Fix) {
        return FixLib.plus(x, y);
    }

    function plusi(Fix x, int256 y) public pure returns (Fix) {
        return FixLib.plusi(x, y);
    }

    function plusu(Fix x, uint256 y) public pure returns (Fix) {
        return FixLib.plusu(x, y);
    }

    function minus(Fix x, Fix y) public pure returns (Fix) {
        return FixLib.minus(x, y);
    }

    function minusi(Fix x, int256 y) public pure returns (Fix) {
        return FixLib.minusi(x, y);
    }

    function minusu(Fix x, uint256 y) public pure returns (Fix) {
        return FixLib.minusu(x, y);
    }

    function mul(Fix x, Fix y) public pure returns (Fix) {
        return FixLib.mul(x, y);
    }

    function muli(Fix x, int256 y) public pure returns (Fix) {
        return FixLib.muli(x, y);
    }

    function mulu(Fix x, uint256 y) public pure returns (Fix) {
        return FixLib.mulu(x, y);
    }

    function div(Fix x, Fix y) public pure returns (Fix) {
        return FixLib.div(x, y);
    }

    function divi(Fix x, int256 y) public pure returns (Fix) {
        return FixLib.divi(x, y);
    }

    function divu(Fix x, uint256 y) public pure returns (Fix) {
        return FixLib.divu(x, y);
    }

    function inv(Fix x) public pure returns (Fix) {
        return FixLib.inv(x);
    }

    function powu(Fix x, uint256 y) public pure returns (Fix) {
        return FixLib.powu(x, y);
    }

    function lt(Fix x, Fix y) public pure returns (bool) {
        return FixLib.lt(x, y);
    }

    function lte(Fix x, Fix y) public pure returns (bool) {
        return FixLib.lte(x, y);
    }

    function gt(Fix x, Fix y) public pure returns (bool) {
        return FixLib.gt(x, y);
    }

    function gte(Fix x, Fix y) public pure returns (bool) {
        return FixLib.gte(x, y);
    }

    function eq(Fix x, Fix y) public pure returns (bool) {
        return FixLib.eq(x, y);
    }

    function neq(Fix x, Fix y) public pure returns (bool) {
        return FixLib.neq(x, y);
    }

    /// Return whether or not this Fix is within epsilon of y.
    function near(
        Fix x,
        Fix y,
        Fix epsilon
    ) public pure returns (bool) {
        return FixLib.near(x, y, epsilon);
    }
}