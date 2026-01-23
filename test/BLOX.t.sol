// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BLOX} from "src/BLOX.sol";

contract BLOXTest is Test {
    BLOX private blox;
    address private alice = address(0xA11CE);

    function setUp() public {
        blox = new BLOX(alice);
    }

    function testBurnReducesBalanceAndTotalSupply() public {
        uint256 burnAmount = 1_000 ether;
        uint256 supplyBefore = blox.totalSupply();
        uint256 balanceBefore = blox.balanceOf(alice);

        vm.prank(alice);
        blox.burn(burnAmount);

        assertEq(blox.totalSupply(), supplyBefore - burnAmount);
        assertEq(blox.balanceOf(alice), balanceBefore - burnAmount);
    }
}
