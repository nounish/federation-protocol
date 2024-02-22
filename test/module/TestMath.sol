// SPDX-License-Identifier: GPL-3.0

import "forge-std/Test.sol";
import {NounsPool} from "src/module/governance-pool/nouns/Nouns.sol";

pragma solidity ^0.8.19;

/// Tests all the math things
contract TestMath is NounsPool, Test {
    function testFuzzBPSToUint(uint256 bps, uint256 number) public pure {
        vm.assume(number != 0);
        vm.assume(bps != 0);
        vm.assume(bps <= 10000);
        vm.assume(number < MAX_INT / 10000);

        // ensure no reversion
        _bpsToUint(bps, number);
    }

    function testBPSToUint() public {
        uint256 proceeds = 29410.6666666 ether;

        uint256 bps = 2313; // 23.13%
        assertEq(
            _bpsToUint(10000 - bps, proceeds) + _bpsToUint(bps, proceeds),
            proceeds
        );

        uint256 r1 = 6676;
        uint256 r2 = 100;
        uint256 r3 = 500;
        uint256 r4 = 2333;
        uint256 r5 = 391;
        assertEq(r1 + r2 + r3 + r4 + r5, 10000);

        uint256 sumRatios = _bpsToUint(r1, proceeds) +
            _bpsToUint(r2, proceeds) +
            _bpsToUint(r3, proceeds) +
            _bpsToUint(r4, proceeds) +
            _bpsToUint(r5, proceeds);
        assertEq(sumRatios, proceeds);
    }
}
