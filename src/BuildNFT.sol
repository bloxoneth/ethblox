// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFeeRegistry {
    function accrueFromComposition(
        uint256[] calldata tokenIds,
        uint256[] calldata counts
    ) external payable;
}

/// @notice Single ERC721 for both "bricks" and "builds" in MVP.
/// Locks BLOX on mint, returns 90% on burn, recycles 10% to RewardsPool.
/// geometryHash uniqueness is permanent (never cleared).
contract BuildNFT is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ==============================
    // Events
    // ==============================

    event BuildMinted(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 mass,
        bytes32 indexed geometryHash,
        string tokenURI
    );

    event BuildBurned(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 mass,
        bytes32 indexed geometryHash,
        uint256 lockedBloxAmount,
        uint256 returnedToOwner,
        uint256 recycledToRewardsPool
    );

    // ==============================
    // Constants
    // ==============================

    uint256 public constant FEE_PER_MINT = 0.01 ether;
    uint256 public constant BLOX_PER_MASS = 1e18;

    // ==============================
    // External addresses
    // ==============================

    IERC20 public immutable blox;

    address public rewardsPool;
    address public feeRegistry;
    address public liquidityReceiver;
    address public protocolTreasury;

    // ==============================
    // Config / state
    // ==============================

    uint256 public maxMass;
    uint256 public nextTokenId = 1;

    mapping(uint256 => uint256) public massOf;
    mapping(uint256 => bytes32) public geometryOf;
    mapping(uint256 => uint256) public lockedBloxOf;
    mapping(uint256 => address) public creatorOf;

    // Permanent invariant — NEVER cleared
    mapping(bytes32 => bool) public usedGeometryHash;

    // ==============================
    // Constructor
    // ==============================

constructor(
    address blox_,
    address rewardsPool_,
    address feeRegistry_,
    address liquidityReceiver_,
    address protocolTreasury_,
    uint256 maxMass_
)
    ERC721("ETHBLOX Build", "BUILD")
    Ownable(msg.sender)
{
        require(blox_ != address(0), "BLOX=0");
        require(rewardsPool_ != address(0), "rewards=0");
        require(feeRegistry_ != address(0), "registry=0");
        require(liquidityReceiver_ != address(0), "liquidity=0");
        require(protocolTreasury_ != address(0), "treasury=0");
        require(maxMass_ > 0, "maxMass=0");

        blox = IERC20(blox_);
        rewardsPool = rewardsPool_;
        feeRegistry = feeRegistry_;
        liquidityReceiver = liquidityReceiver_;
        protocolTreasury = protocolTreasury_;
        maxMass = maxMass_;
    }

    // ==============================
    // Mint
    // ==============================

    function mint(
        bytes32 geometryHash,
        uint256 mass,
        string calldata uri,
        uint256[] calldata componentTokenIds,
        uint256[] calldata componentCounts
    ) external payable nonReentrant returns (uint256 tokenId) {
        require(msg.value == FEE_PER_MINT, "bad fee");
        require(mass > 0, "mass=0");
        require(mass <= maxMass, "mass>max");
        require(!usedGeometryHash[geometryHash], "hash used");

        uint256 lockAmount = mass * BLOX_PER_MASS;
        blox.safeTransferFrom(msg.sender, address(this), lockAmount);

        usedGeometryHash[geometryHash] = true;

        tokenId = nextTokenId++;
        massOf[tokenId] = mass;
        geometryOf[tokenId] = geometryHash;
        lockedBloxOf[tokenId] = lockAmount;
        creatorOf[tokenId] = msg.sender;

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, uri);

        _payETH(liquidityReceiver, 0.003 ether);
        _payETH(protocolTreasury, 0.002 ether);

        if (componentTokenIds.length == 0) {
            _payETH(protocolTreasury, 0.005 ether);
        } else {
            IFeeRegistry(feeRegistry).accrueFromComposition{value: 0.005 ether}(
                componentTokenIds,
                componentCounts
            );
        }

        emit BuildMinted(tokenId, msg.sender, mass, geometryHash, uri);
    }

    // ==============================
    // Burn
    // ==============================

    function burn(uint256 tokenId) external nonReentrant {
        address owner = ownerOf(tokenId);
require(
    msg.sender == owner ||
    getApproved(tokenId) == msg.sender ||
    isApprovedForAll(owner, msg.sender),
    "not owner/approved"
);
        uint256 mass = massOf[tokenId];
        bytes32 gh = geometryOf[tokenId];
        uint256 locked = lockedBloxOf[tokenId];

        uint256 recycled = locked / 10;
        uint256 returned = locked - recycled;

        delete massOf[tokenId];
        delete geometryOf[tokenId];
        delete lockedBloxOf[tokenId];
        delete creatorOf[tokenId];

        _burn(tokenId);

        blox.safeTransfer(owner, returned);
        blox.safeTransfer(rewardsPool, recycled);

        emit BuildBurned(tokenId, owner, mass, gh, locked, returned, recycled);
    }

    // ==============================
    // Admin setters
    // ==============================

    function setMaxMass(uint256 newMaxMass) external onlyOwner {
        require(newMaxMass > 0, "maxMass=0");
        maxMass = newMaxMass;
    }

    function setLiquidityReceiver(address a) external onlyOwner {
        require(a != address(0), "0");
        liquidityReceiver = a;
    }

    function setProtocolTreasury(address a) external onlyOwner {
        require(a != address(0), "0");
        protocolTreasury = a;
    }

    function setFeeRegistry(address a) external onlyOwner {
        require(a != address(0), "0");
        feeRegistry = a;
    }

    function setRewardsPool(address a) external onlyOwner {
        require(a != address(0), "0");
        rewardsPool = a;
    }

    // ==============================
    // Internals
    // ==============================

    function _payETH(address to, uint256 amount) internal {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "ETH transfer failed");
    } 
function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721URIStorage)
    returns (bool)
{
    return super.supportsInterface(interfaceId);
}
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return ERC721URIStorage.tokenURI(tokenId);
    }
}