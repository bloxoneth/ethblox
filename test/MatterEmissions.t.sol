// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BLOX} from "src/BLOX.sol";
import {Distributor} from "src/Distributor.sol";
import {MatterEmissions} from "src/MatterEmissions.sol";

contract MatterEmissionsTest is Test {
    BLOX private blox;
    Distributor private distributor;
    MatterEmissions private emissions;

    function setUp() public {
        blox = new BLOX(address(this));
        distributor = new Distributor(address(blox), address(this));
        emissions = new MatterEmissions(address(blox), address(distributor), 86_400 ether);

        blox.transfer(address(emissions), 1_000_000 ether);
    }

    function testDistributorStoresBlox() public {
        assertEq(address(distributor.blox()), address(blox));
    }

    function testDistributorRevertsOnZeroAddress() public {
        vm.expectRevert(bytes("BLOX=0"));
new Distributor(address(0), address(this));
    }

    function testEmissionsTransfersLinearly() public {
        uint256 start = emissions.startTime();
        vm.warp(start + 10);

        uint256 distributorBefore = blox.balanceOf(address(distributor));
        uint256 releasable = emissions.releasable();

        emissions.release();

        assertEq(releasable, 10 ether);
        assertEq(blox.balanceOf(address(distributor)), distributorBefore + 10 ether);
        assertEq(emissions.totalReleased(), 10 ether);
    }

    function testEmitRevertsWhenNoElapsedTime() public {
        vm.expectRevert(bytes("nothing to emit"));
        emissions.release();
    }

    function testEmissionsRevertsOnZeroAddresses() public {
        vm.expectRevert(bytes("BLOX=0"));
        new MatterEmissions(address(0), address(distributor), 1 ether);

        vm.expectRevert(bytes("distributor=0"));
        new MatterEmissions(address(blox), address(0), 1 ether);

        vm.expectRevert(bytes("emission=0"));
        new MatterEmissions(address(blox), address(distributor), 0);
    }
}
