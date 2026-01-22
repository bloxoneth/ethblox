// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title BLOX
/// @notice Fixed-supply ERC20 used to back ETHBLOX builds.
/// Supply is minted once at deployment.
contract BLOX is ERC20 {
    constructor(uint256 totalSupply, address recipient) ERC20("BLOX", "BLOX") {
        require(recipient != address(0), "recipient=0");
        _mint(recipient, totalSupply);
    }
}
