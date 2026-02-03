// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BuildNFT} from "src/BuildNFT.sol";
import {Distributor} from "src/Distributor.sol";
import {LicenseNFT} from "src/LicenseNFT.sol";
import {LicenseRegistry} from "src/LicenseRegistry.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract BuildNFTTest is Test {
    BuildNFT private buildNFT;
    LicenseNFT private licenseNFT;
    LicenseRegistry private licenseRegistry;
    ERC20Mock private blox;
    Distributor private distributor;

    address private liquidityReceiver = address(0x200);
    address private protocolTreasury = address(0x300);
    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);

    function setUp() public {
        uint256 nonce = vm.getNonce(address(this));
        address predictedBuild = vm.computeCreateAddress(address(this), nonce + 4);

        blox = new ERC20Mock();
        distributor = new Distributor(address(blox), address(this));
        licenseNFT = new LicenseNFT("ipfs://licenses");
        licenseRegistry = new LicenseRegistry(predictedBuild, address(licenseNFT), protocolTreasury);
        buildNFT = new BuildNFT(
            address(blox),
            address(distributor),
            liquidityReceiver,
            protocolTreasury,
            address(licenseRegistry),
            address(licenseNFT),
            1_000
        );
        licenseNFT.setRegistry(address(licenseRegistry));
        distributor.setBuildNFT(address(buildNFT));
        distributor.setProtocolTreasury(protocolTreasury);

        blox.mint(address(this), 2_000 ether);
        blox.transfer(alice, 1_000 ether);
        blox.transfer(bob, 1_000 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function _mintAs(
        address minter,
        bytes32 geo,
        uint256 mass,
        uint256[] memory componentTokenIds,
        uint256[] memory componentCounts
    ) internal returns (uint256 tokenId) {
        uint256 lockAmount = mass * buildNFT.BLOX_PER_MASS();

        vm.startPrank(minter);
        blox.approve(address(buildNFT), lockAmount);
        tokenId = buildNFT.mint{value: buildNFT.FEE_PER_MINT()}(
            geo,
            mass,
            "ipfs://test",
            componentTokenIds,
            componentCounts
        );
        vm.stopPrank();
    }

    function _mintAsAlice(bytes32 geo, uint256 mass) internal returns (uint256 tokenId) {
        uint256[] memory emptyTokenIds = new uint256[](0);
        uint256[] memory emptyCounts = new uint256[](0);

        tokenId = _mintAs(alice, geo, mass, emptyTokenIds, emptyCounts);
    }

    function testGeometryReusableAfterBurn() public {
        bytes32 geo = keccak256("geo-reuse");
        uint256 mass = 5;

        uint256 tokenId = _mintAsAlice(geo, mass);

        vm.prank(alice);
        buildNFT.burn(tokenId);

        uint256 newTokenId = _mintAsAlice(geo, mass);

        assertEq(buildNFT.geometryOf(newTokenId), geo);
        assertTrue(buildNFT.geometryInUse(geo));
    }

    function testFeeRouting_NoComponentsGoesToTreasury() public {
        bytes32 geo = keccak256("geo-fee-no-components");
        uint256 mass = 4;
        uint256 fee = buildNFT.FEE_PER_MINT();

        uint256 liquidityBefore = liquidityReceiver.balance;
        uint256 treasuryBefore = protocolTreasury.balance;

        _mintAsAlice(geo, mass);

        uint256 liquidityCut = (fee * 30) / 100;
        uint256 treasuryCut = (fee * 20) / 100;
        uint256 ownersCut = fee - liquidityCut - treasuryCut;

        assertEq(liquidityReceiver.balance, liquidityBefore + liquidityCut);
        assertEq(protocolTreasury.balance, treasuryBefore + treasuryCut + ownersCut);
    }

    function testFeeRouting_WithComponentsAccruesToComponentOwner() public {
        bytes32 bobGeo = keccak256("geo-component");
        uint256 mass = 3;
        uint256[] memory emptyTokenIds = new uint256[](0);
        uint256[] memory emptyCounts = new uint256[](0);

        uint256 componentId = _mintAs(bob, bobGeo, mass, emptyTokenIds, emptyCounts);

        vm.prank(bob);
        licenseRegistry.registerBuild(componentId, bobGeo, 10, 0, 0);

        uint256 licensePrice = licenseRegistry.quote(componentId, 1);
        vm.prank(alice);
        licenseRegistry.mintLicenseForBuild{value: licensePrice}(componentId, 1);
        vm.prank(alice);
        licenseNFT.setApprovalForAll(address(buildNFT), true);

        uint256[] memory componentTokenIds = new uint256[](1);
        uint256[] memory componentCounts = new uint256[](1);
        componentTokenIds[0] = componentId;
        componentCounts[0] = 1;

        uint256 fee = buildNFT.FEE_PER_MINT();
        uint256 liquidityBefore = liquidityReceiver.balance;
        uint256 treasuryBefore = protocolTreasury.balance;
        uint256 bobAccruedBefore = distributor.ethOwed(bob);
        uint256 treasuryAccruedBefore = distributor.ethOwed(protocolTreasury);

        _mintAs(alice, keccak256("geo-fee-components"), 5, componentTokenIds, componentCounts);

        uint256 liquidityCut = (fee * 30) / 100;
        uint256 treasuryCut = (fee * 20) / 100;
        uint256 ownersCut = fee - liquidityCut - treasuryCut;

        assertEq(liquidityReceiver.balance, liquidityBefore + liquidityCut);
        assertEq(protocolTreasury.balance, treasuryBefore + treasuryCut);
        assertEq(distributor.ethOwed(bob), bobAccruedBefore + ownersCut);
        assertEq(distributor.ethOwed(protocolTreasury), treasuryAccruedBefore);
    }
}
