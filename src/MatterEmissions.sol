// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MatterEmissions {
    using SafeERC20 for IERC20;

    IERC20 public immutable blox;
    address public immutable distributor;

    uint256 public immutable startTime;
    uint256 public immutable dailyEmission; // BLOX wei (18 decimals)

    uint256 public totalReleased; // total BLOX sent so far

    constructor(address blox_, address distributor_, uint256 dailyEmission_) {
        require(blox_ != address(0), "BLOX=0");
        require(distributor_ != address(0), "distributor=0");
        require(dailyEmission_ > 0, "emission=0");

        blox = IERC20(blox_);
        distributor = distributor_;
        dailyEmission = dailyEmission_;

        startTime = block.timestamp;
    }

    function releasable() public view returns (uint256) {
        uint256 elapsed = block.timestamp - startTime;

        // Total scheduled since start (linear), with remainder naturally carried forward
        uint256 scheduled = (elapsed * dailyEmission) / 1 days;

        if (scheduled <= totalReleased) return 0;

        uint256 amount = scheduled - totalReleased;

        uint256 available = blox.balanceOf(address(this));
        if (amount > available) amount = available;

        return amount;
    }

    function release() external {
        uint256 amount = releasable();
        require(amount > 0, "nothing to emit"); // A: accrue while unfunded

        totalReleased += amount;
        blox.safeTransfer(distributor, amount);
    }
}