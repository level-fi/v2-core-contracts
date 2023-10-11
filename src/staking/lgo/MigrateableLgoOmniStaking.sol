// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBurnableERC20} from "../../interfaces/IBurnableERC20.sol";
import "./../LevelOmniStaking.sol";

/**
 * @title MigrateableLgoOmniStaking
 * @notice Staking contract which accept migrate LGO from legacy contract
 */
contract MigrateableLgoOmniStaking is LevelOmniStaking {
    using SafeERC20 for IBurnableERC20;

    address public stakingV1;

    function setStakingV1(address _stakingV1) external onlyOwner {
        require(stakingV1 == address(0), "Already set");
        stakingV1 = _stakingV1;
        emit StakingV1Set(_stakingV1);
    }

    /**
     * @notice Allow stake without tax, only from legacy staking contract
     */
    function migrateStake(address _to, uint256 _amount) external whenNotPaused nonReentrant {
        require(msg.sender == stakingV1, "!stakingV1");
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Invalid amount");
        _updateCurrentEpoch();
        _updateUser(_to, _amount, true);
        totalStaked += _amount;
        stakeToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _to, currentEpoch, _amount, 0);
    }

    event StakingV1Set(address stakingV1);
}
