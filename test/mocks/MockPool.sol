pragma solidity >=0.8.0;

import {ILPToken} from "../../src/interfaces/ILPToken.sol";
import {LPToken} from "./MockLpToken.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// struct PoolTokenInfo {
//     /// @notice amount reserved for fee
//     uint256 feeReserve;
//     /// @notice recorded balance of token in pool
//     uint256 poolBalance;
//     /// @notice last borrow index update timestamp
//     uint256 lastAccrualTimestamp;
//     /// @notice accumulated interest rate
//     uint256 borrowIndex;
//     /// @notice average entry price of all short position
//     uint256 averageShortPrice;
// }

contract MockPool {
    using SafeERC20 for IERC20;

    ILPToken public lpToken;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    mapping(address => uint256) public feeReserves;
    mapping(address => uint256) public poolBalances;

    function setLpToken(address lp) external {
        lpToken = ILPToken(lp);
    }

    function addLiquidity(
        address, /* _tranche */
        address _token,
        uint256 _amount,
        uint256, /* _minLpAmount */
        address _to
    ) external payable {
        if (_token != ETH) {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
        lpToken.mint(_to, _amount);
    }

    function removeLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount, uint256, /* _minOut */ address _to)
        external
    {
        IERC20(_tranche).safeTransferFrom(msg.sender, address(this), _lpAmount);
        IERC20(_tokenOut).safeTransfer(_to, _lpAmount);
    }

    function withdrawFee(address _token, address _recipient) external {
        uint256 amount = feeReserves[_token];
        feeReserves[_token] = 0;
        IERC20(_token).transfer(_recipient, amount);
    }

    function setFeeReserve(address _token, uint256 amount) external {
        feeReserves[_token] = amount;
    }

    function setPoolBalance(address _token, uint256 amount) external {
        poolBalances[_token] = amount;
    }

    function swap(address _tokenIn, address _tokenOut, uint256, address _to, bytes calldata) external {
        uint256 outAmount = IERC20(_tokenIn).balanceOf(address(this)) - poolBalances[_tokenIn];
        IERC20(_tokenOut).safeTransfer(_to, outAmount);
        poolBalances[_tokenIn] += outAmount;
        poolBalances[_tokenOut] -= outAmount;
    }
}
