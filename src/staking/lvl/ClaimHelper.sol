// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "../../interfaces/IPool.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {IETHUnwrapper} from "../../interfaces/IETHUnwrapper.sol";
import {ILevelOmniStaking} from "../../interfaces/ILevelOmniStaking.sol";

contract ClaimHelper {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    IERC20 public LLP;
    IWETH public WETH;

    IPool public pool;
    IETHUnwrapper public ethUnwrapper;

    ILevelOmniStaking public lvlStaking;
    ILevelOmniStaking public lvlUsdtStaking;

    constructor(
        address _pool,
        address _llp,
        address _weth,
        address _ethUnwrapper,
        address _lvlStaking,
        address _lvlUsdtStaking
    ) {
        if (_pool == address(0)) revert ZeroAddress();
        if (_llp == address(0)) revert ZeroAddress();
        if (_weth == address(0)) revert ZeroAddress();
        if (_ethUnwrapper == address(0)) revert ZeroAddress();
        if (_lvlStaking == address(0)) revert ZeroAddress();
        if (_lvlUsdtStaking == address(0)) revert ZeroAddress();
        pool = IPool(_pool);
        LLP = IERC20(_llp);
        WETH = IWETH(_weth);
        ethUnwrapper = IETHUnwrapper(_ethUnwrapper);
        lvlStaking = ILevelOmniStaking(_lvlStaking);
        lvlUsdtStaking = ILevelOmniStaking(_lvlUsdtStaking);
    }

    // =============== USER FUNCTIONS ===============
    function claimRewards(uint256[] calldata _epochs, address _to) external {
        _claimRewards(_epochs, _to);
    }

    function claimRewardsToSingleToken(
        uint256[] calldata _epochs,
        address _to,
        address _tokenOut,
        uint256 _minAmountOut
    ) external {
        uint256 _beforeLLPBalance = LLP.balanceOf(address(this));
        _claimRewards(_epochs, address(this));
        uint256 _llpAmount = LLP.balanceOf(address(this)) - _beforeLLPBalance;
        _convertLLPToToken(_to, _llpAmount, _tokenOut, _minAmountOut);
    }

    // =============== INTERNAL FUNCTIONS ===============
    function _claimRewards(uint256[] calldata _epochs, address _to) internal {
        uint256 _length = _epochs.length;
        for (uint256 i = 0; i < _length;) {
            uint256 _epoch = _epochs[i];
            lvlStaking.claimRewardsOnBehalf(msg.sender, _epoch, _to);
            lvlUsdtStaking.claimRewardsOnBehalf(msg.sender, _epoch, _to);

            unchecked {
                ++i;
            }
        }
    }

    function _convertLLPToToken(address _to, uint256 _amount, address _tokenOut, uint256 _minAmountOut)
        internal
        returns (uint256)
    {
        LLP.safeIncreaseAllowance(address(pool), _amount);
        uint256 _balanceBefore = IERC20(_tokenOut).balanceOf(address(this));
        pool.removeLiquidity(address(LLP), _tokenOut, _amount, _minAmountOut, address(this));
        uint256 _amountOut = IERC20(_tokenOut).balanceOf(address(this)) - _balanceBefore;
        if (_amountOut < _minAmountOut) revert Slippage();
        _safeTransferToken(_tokenOut, _to, _amountOut);
        return _amountOut;
    }

    function _safeTransferToken(address _token, address _to, uint256 _amount) internal {
        if (_amount > 0) {
            if (_token == address(WETH)) {
                _safeUnwrapETH(_to, _amount);
            } else {
                IERC20(_token).safeTransfer(_to, _amount);
            }
        }
    }

    function _safeUnwrapETH(address _to, uint256 _amount) internal {
        WETH.safeIncreaseAllowance(address(ethUnwrapper), _amount);
        ethUnwrapper.unwrap(_amount, _to);
    }

    // =============== ERRORS ===============
    error ZeroAddress();
    error Slippage();
}
