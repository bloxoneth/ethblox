// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {LicenseRegistry} from "src/LicenseRegistry.sol";
import {LicenseNFT} from "src/LicenseNFT.sol";

/// @dev Minimal BuildNFT stub for registry tests.
contract MockBuildNFT {
    mapping(uint256 => address) internal _ownerOf;
    mapping(uint256 => bytes32) internal _geometryOf;

    function setOwner(uint256 tokenId, address owner) external {
        _ownerOf[tokenId] = owner;
    }

    function setGeometry(uint256 tokenId, bytes32 g) external {
        _geometryOf[tokenId] = g;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _ownerOf[tokenId];
        require(o != address(0), "NONEXISTENT");
        return o;
    }

    function geometryOf(uint256 tokenId) external view returns (bytes32) {
        // mirror your real BuildNFT pattern: geometryOf for non-existent tokens is fine
        // as long as ownerOf is the authoritative existence check.
        return _geometryOf[tokenId];
    }
}

contract LicenseRegistryTest is Test {
    MockBuildNFT private build;
    LicenseNFT private licenseNFT;
    LicenseRegistry private registry;

    address private deployer = address(this);
    address private buildOwner = address(0xB0B);
    address private buyer = address(0xA11CE);

    address payable private treasury = payable(address(0xBEEF));
    address payable private newTreasury = payable(address(0xCAFE));

    uint256 private buildId = 1;
    bytes32 private geo = keccak256("geo-1");

    function setUp() public {
        build = new MockBuildNFT();
        build.setOwner(buildId, buildOwner);
        build.setGeometry(buildId, geo);

        licenseNFT = new LicenseNFT("ipfs://base/{id}.json");

        // Deploy registry with treasury
        registry = new LicenseRegistry(address(build), address(licenseNFT), treasury);

        // Wire permissions: only registry can mint + set max supply
        licenseNFT.setRegistry(address(registry));

        // Fund buyer with ETH
        vm.deal(buyer, 100 ether);
    }

    // ---------- constructor / admin ----------

    function testConstructorSetsState() public {
        assertEq(registry.buildNFT(), address(build));
        assertEq(registry.licenseNFT(), address(licenseNFT));
        assertEq(registry.treasury(), treasury);
        assertEq(registry.owner(), deployer);
    }

    function testSetTreasuryOnlyOwner() public {
        // Non-owner should revert (message depends on OZ version; keep generic)
        vm.prank(buyer);
        vm.expectRevert();
        registry.setTreasury(newTreasury);

        // Owner can set
        registry.setTreasury(newTreasury);
        assertEq(registry.treasury(), newTreasury);
    }

    // ---------- registerBuild ----------

    function testRegisterBuildHappyPath() public {
        vm.prank(buildOwner);
        registry.registerBuild(buildId, geo, 1000, 0.01 ether, 0.001 ether);

        uint256 licenseId = registry.licenseIdForBuild(buildId);
        assertEq(licenseId, 1);

        (uint256 startPrice, uint256 step, uint256 maxSupply) = registry.pricingForLicense(licenseId);
        assertEq(startPrice, 0.01 ether);
        assertEq(step, 0.001 ether);
        assertEq(maxSupply, 1000);

        // LicenseNFT maxSupply should be set
        assertEq(licenseNFT.maxSupply(licenseId), 1000);
    }

    function testRegisterBuildRevertsIfNotOwner() public {
        vm.prank(buyer);
        vm.expectRevert(bytes("not owner"));
        registry.registerBuild(buildId, geo, 1000, 0.01 ether, 0.001 ether);
    }

    function testRegisterBuildRevertsOnGeometryMismatch() public {
        vm.prank(buildOwner);
        vm.expectRevert(bytes("geometry mismatch"));
        registry.registerBuild(buildId, keccak256("wrong"), 1000, 0.01 ether, 0.001 ether);
    }

    function testRegisterBuildRevertsIfAlreadyRegistered() public {
        vm.prank(buildOwner);
        registry.registerBuild(buildId, geo, 1000, 0.01 ether, 0.001 ether);

        vm.prank(buildOwner);
        vm.expectRevert(bytes("already registered"));
        registry.registerBuild(buildId, geo, 1000, 0.01 ether, 0.001 ether);
    }

    function testRegisterBuildRevertsOnZeroMax() public {
        vm.prank(buildOwner);
        vm.expectRevert(bytes("max=0"));
        registry.registerBuild(buildId, geo, 0, 0.01 ether, 0.001 ether);
    }

    // ---------- quote / mintLicenseForBuild ----------

    function testQuoteMatchesArithmeticSeries() public {
        vm.prank(buildOwner);
        registry.registerBuild(buildId, geo, 1000, 0.01 ether, 0.001 ether);

        // qty=3 -> a + (a+d) + (a+2d) = 0.01 + 0.011 + 0.012 = 0.033 ether
        uint256 q = registry.quote(buildId, 3);
        assertEq(q, 0.033 ether);
    }

    function testMintLicenseForBuildMintsAndForwardsETH() public {
        vm.prank(buildOwner);
        registry.registerBuild(buildId, geo, 1000, 0.01 ether, 0.001 ether);

        uint256 licenseId = registry.licenseIdForBuild(buildId);
        uint256 price = registry.quote(buildId, 2); // 0.01 + 0.011 = 0.021
        assertEq(price, 0.021 ether);

        uint256 treasuryBefore = treasury.balance;

        vm.prank(buyer);
        registry.mintLicenseForBuild{value: price}(buildId, 2);

        // Buyer received ERC1155 licenses
        assertEq(licenseNFT.balanceOf(buyer, licenseId), 2);

        // ETH forwarded to treasury
        assertEq(treasury.balance, treasuryBefore + price);
    }

    function testMintLicenseForBuildRevertsOnBadPrice() public {
        vm.prank(buildOwner);
        registry.registerBuild(buildId, geo, 1000, 0.01 ether, 0.001 ether);

        uint256 price = registry.quote(buildId, 2);

        vm.prank(buyer);
        vm.expectRevert(bytes("bad price"));
        registry.mintLicenseForBuild{value: price - 1}(buildId, 2);
    }

    function testMintLicenseForBuildRevertsIfNotRegistered() public {
        vm.prank(buyer);
        vm.expectRevert(bytes("not registered"));
        registry.mintLicenseForBuild{value: 1 ether}(buildId, 1);
    }

    function testQuoteRevertsIfNotRegistered() public {
        vm.expectRevert(bytes("not registered"));
        registry.quote(buildId, 1);
    }
}
