// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBurnableERC20} from "../../interfaces/IBurnableERC20.sol";
import {ILevelNormalVesting} from "../../interfaces/ILevelNormalVesting.sol";
import "./../LevelOmniStaking.sol";

/**
 * @title MigrateableLevelOmniStaking
 * @notice Staking contract which accept migrate stake token from legacy contract
 */
contract MigrateableLevelOmniStaking is LevelOmniStaking {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBurnableERC20;

    uint8 constant VERSION = 2;

    address public stakingV1;
    /**
     * @notice list of address with tax discount. Allow vesting Investor fund can restake their fund without permenent loss
     */
    mapping(address user => bool) public whitelistedUser;

    ILevelNormalVesting public normalVestingLVL;
    address public stakingHelper;
    address public claimHelper;

    // =============== USER FUNCTIONS ===============
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

    function stake(address _to, uint256 _amount) external override whenNotPaused nonReentrant {
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Invalid amount");
        uint256 _tax = whitelistedUser[_to] ? 0 : STAKING_TAX;
        uint256 _taxAmount = (_amount * _tax) / STAKING_TAX_PRECISION;
        uint256 _stakedAmount = _amount - _taxAmount;
        _updateCurrentEpoch();
        _updateUser(_to, _stakedAmount, true);
        totalStaked += _stakedAmount;
        stakeToken.safeTransferFrom(msg.sender, address(this), _amount);
        if (_taxAmount != 0) {
            stakeToken.burn(_taxAmount);
        }
        emit Staked(msg.sender, _to, currentEpoch, _stakedAmount, _taxAmount);
    }

    function unstake(address _to, uint256 _amount) external override whenNotPaused nonReentrant {
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Invalid amount");
        address _sender = msg.sender;
        uint256 _reservedForVesting = 0;
        if (address(normalVestingLVL) != address(0)) {
            _reservedForVesting = normalVestingLVL.getReservedAmount(_sender);
        }
        require(_amount + _reservedForVesting <= stakedAmounts[_sender], "Insufficient staked amount");
        _updateCurrentEpoch();
        _updateUser(_sender, _amount, false);
        totalStaked -= _amount;
        stakeToken.safeTransfer(_to, _amount);
        emit Unstaked(_sender, _to, currentEpoch, _amount);
    }

    /**
     * @notice Support multiple claim, only `claimHelper` can call this function.
     */
    function claimRewardsOnBehalf(address _user, uint256 _epoch, address _to) external whenNotPaused nonReentrant {
        require(msg.sender == claimHelper, "Only claimHelper");
        _claimRewards(_user, _epoch, _to);
    }

    /**
     * @notice Support multiple claim, only `claimHelper` can call this function.
     */
    function claimRewardsToSingleTokenOnBehalf(
        address _user,
        uint256 _epoch,
        address _to,
        address _tokenOut,
        uint256 _minAmountOut
    ) external whenNotPaused nonReentrant {
        require(msg.sender == claimHelper, "Only claimHelper");
        _claimRewardsToSingleToken(_user, _epoch, _to, _tokenOut, _minAmountOut);
    }

    /**
     * @dev UNUSED: Update new business
     */
    function allocateReward(uint256 _epoch) external override onlyDistributorOrOwner {
        // doing nothing
    }

    /**
     * @dev @dev UNUSED: Update new business
     */
    function allocateReward(uint256 _epoch, address[] calldata _tokens, uint256[] calldata _amounts)
        external
        override
        onlyDistributorOrOwner
    {
        // doing nothing
    }

    function allocateReward(uint256 _epoch, uint256 _rewardAmount) external {
        require(msg.sender == stakingHelper, "Only stakingHelper");
        EpochInfo memory _epochInfo = epochs[_epoch];
        require(_epochInfo.endTime != 0, "Epoch not ended");
        require(_epochInfo.allocationTime == 0, "Reward allocated");
        require(_rewardAmount != 0, "Reward = 0");
        _epochInfo.totalReward = _rewardAmount;
        _epochInfo.allocationTime = block.timestamp;
        epochs[_epoch] = _epochInfo;
        LLP.safeTransferFrom(msg.sender, address(this), _rewardAmount);
        emit RewardAllocated(_epoch, _rewardAmount);
    }

    // =============== RESTRICTED ===============
    function setStakingV1(address _stakingV1) external onlyOwner {
        require(stakingV1 == address(0), "Already set");
        stakingV1 = _stakingV1;
        emit StakingV1Set(_stakingV1);
    }

    function setNormalVestingLVL(address _normalVestingLVL) external onlyOwner {
        require(_normalVestingLVL != address(0), "Invalid address");
        normalVestingLVL = ILevelNormalVesting(_normalVestingLVL);
        emit LevelNormalVestingSet(_normalVestingLVL);
    }

    function setStakingHelper(address _stakingHelper) external onlyOwner {
        stakingHelper = _stakingHelper;
        emit StakingHelperSet(_stakingHelper);
    }

    function setClaimHelper(address _claimHelper) external onlyOwner {
        claimHelper = _claimHelper;
        emit ClaimHelperSet(_claimHelper);
    }

    // =============== EVENTS ===============
    event StakingV1Set(address _stakingV1);
    event LevelNormalVestingSet(address _normalVestingLVL);
    event StakingHelperSet(address _stakingHelper);
    event ClaimHelperSet(address _claimHelper);
}
