// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ILevelOmniStakingReserve} from "../../interfaces/ILevelOmniStakingReserve.sol";
import {ILevelOmniStaking} from "../../interfaces/ILevelOmniStaking.sol";
import {IMultiplierTracker} from "../../interfaces/IMultiplierTracker.sol";

contract LevelOmniStakingHelper is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant MULTIPLIER_PRECISION = 1e6;

    IERC20 public LLP;
    ILevelOmniStakingReserve public stakingReserve;
    ILevelOmniStaking public lvlStaking;
    ILevelOmniStaking public lvlUsdtStaking;
    IMultiplierTracker public multiplierTracker;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _llp,
        address _stakingReserve,
        address _lvlStaking,
        address _lvlUsdtStaking,
        address _multiplierTracker
    ) external initializer {
        if (_llp == address(0)) revert ZeroAddress();
        if (_stakingReserve == address(0)) revert ZeroAddress();
        if (_lvlStaking == address(0)) revert ZeroAddress();
        if (_lvlUsdtStaking == address(0)) revert ZeroAddress();
        if (_multiplierTracker == address(0)) revert ZeroAddress();
        __Ownable_init();
        LLP = IERC20(_llp);
        stakingReserve = ILevelOmniStakingReserve(_stakingReserve);
        lvlStaking = ILevelOmniStaking(_lvlStaking);
        lvlUsdtStaking = ILevelOmniStaking(_lvlUsdtStaking);
        multiplierTracker = IMultiplierTracker(_multiplierTracker);
    }

    // =============== VIEW FUNCTIONS ===============
    function getLvlUsdtMultiplier() external view returns (uint256) {
        return _getLvlUsdtMultiplier();
    }

    // =============== USER FUNCTIONS ===============
    function nextEpoch() external {
        lvlStaking.nextEpoch();
        lvlUsdtStaking.nextEpoch();
    }

    function allocate(uint256 _epoch) external onlyOwner {
        stakingReserve.convertTokenToLLP(address(this));
        _allocate(_epoch);
    }

    function allocate(uint256 _epoch, address[] calldata _tokens, uint256[] calldata _amounts) external onlyOwner {
        stakingReserve.convertTokenToLLP(_tokens, _amounts, address(this));
        _allocate(_epoch);
    }

    // =============== INTERNAL FUNCTIONS ===============
    function _getStakingShare(address _staking, uint256 _epoch, uint256 _multiplier) internal view returns (uint256) {
        (,,, uint256 _stakingShare,,) = ILevelOmniStaking(_staking).epochs(_epoch);
        return _stakingShare * _multiplier;
    }

    function _allocate(uint256 _epoch) internal {
        uint256 _lvlStakingShare = _getStakingShare(address(lvlStaking), _epoch, MULTIPLIER_PRECISION);
        uint256 _lvlUsdtStakingShare = _getStakingShare(address(lvlUsdtStaking), _epoch, _getLvlUsdtMultiplier());
        uint256 _totalShare = _lvlStakingShare + _lvlUsdtStakingShare;
        if (_totalShare == 0) revert ZeroShare();
        uint256 _lvlStakingAmount = LLP.balanceOf(address(this)) * _lvlStakingShare / _totalShare;
        LLP.approve(address(lvlStaking), _lvlStakingAmount);
        lvlStaking.allocateReward(_epoch, _lvlStakingAmount);
        uint256 _lvlUsdtStakingAmount = LLP.balanceOf(address(this));
        LLP.approve(address(lvlUsdtStaking), _lvlUsdtStakingAmount);
        lvlUsdtStaking.allocateReward(_epoch, _lvlUsdtStakingAmount);

        emit Allocated(_epoch, _lvlStakingAmount, _lvlUsdtStakingAmount);
    }

    function _getLvlUsdtMultiplier() internal view returns (uint256) {
        return multiplierTracker.getStakingMultiplier();
    }

    // =============== ERRORS ===============
    error ZeroAddress();
    error ZeroShare();

    // =============== EVENTS ===============
    event Allocated(uint256 indexed _epoch, uint256 _lvlStakingAmount, uint256 _lvlUsdtStakingAmount);
}
