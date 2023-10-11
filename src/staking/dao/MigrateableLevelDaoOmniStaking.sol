// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./LevelDaoOmniStaking.sol";

/**
 * @title MigrateableLevelDaoOmniStaking
 * @author Level
 * @notice Staking contract which accept `LevelStake` migrate and household management for investor.
 */
contract MigrateableLevelDaoOmniStaking is LevelDaoOmniStaking {
    using SafeERC20 for IERC20;

    address public levelStake;

    function unstakeOnBehalf(address _user, address _to, uint256 _amount) external nonReentrant {
        if (msg.sender != levelStake) revert Unauthorized();
        _unstake(_user, _to, _amount);
    }

    function claimRewardsOnBehalf(address _user, uint256 _epoch, address _to)
        external
        override
        whenNotPaused
        nonReentrant
    {
        if (msg.sender != claimHelper && msg.sender != levelStake) revert Unauthorized();
        _claimRewards(_user, _epoch, _to);
    }

    function setLevelStake(address _levelStake) external onlyOwner {
        levelStake = _levelStake;
        emit LevelStakeSet(_levelStake);
    }

    event LevelStakeSet(address indexed _levelStake);
}
