// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IPool} from "../../interfaces/IPool.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {IETHUnwrapper} from "../../interfaces/IETHUnwrapper.sol";

contract LevelOmniStakingReserve is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    IERC20 public LLP;
    IWETH public WETH;

    IPool public pool;
    IETHUnwrapper public ethUnwrapper;
    address public distributor;

    /// @notice the protocol generate fee in the form of these tokens
    mapping(address => bool) public feeTokens;
    /// @notice list of tokens allowed to convert to LLP. Other fee tokens MUST be manual swapped to these tokens before converting
    address[] public convertLLPTokens;
    /// @notice tokens allowed to convert to LLP, in form of map for fast checking
    mapping(address => bool) public isConvertLLPTokens;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _pool, address _llp, address _weth, address _ethUnwrapper) external initializer {
        if (_pool == address(0)) revert ZeroAddress();
        if (_llp == address(0)) revert ZeroAddress();
        if (_weth == address(0)) revert ZeroAddress();
        if (_ethUnwrapper == address(0)) revert ZeroAddress();
        __Ownable_init();
        pool = IPool(_pool);
        LLP = IERC20(_llp);
        WETH = IWETH(_weth);
        ethUnwrapper = IETHUnwrapper(_ethUnwrapper);
    }

    modifier onlyDistributorOrOwner() {
        _checkDistributorOrOwner();
        _;
    }

    // =============== RESTRICTED ===============
    function convertTokenToLLP(address _to) external onlyDistributorOrOwner {
        if (_to == address(0)) revert ZeroAddress();
        for (uint8 i = 0; i < convertLLPTokens.length;) {
            address _token = convertLLPTokens[i];
            uint256 _amount = IERC20(_token).balanceOf(address(this));
            _convertTokenToLLP(_token, _amount);
            unchecked {
                ++i;
            }
        }
        uint256 _llpBalance = LLP.balanceOf(address(this));
        LLP.safeTransfer(_to, _llpBalance);
        emit LLPConverted(_to, _llpBalance);
    }

    function convertTokenToLLP(address[] calldata _tokens, uint256[] calldata _amounts, address _to)
        external
        onlyDistributorOrOwner
    {
        if (_to == address(0)) revert ZeroAddress();
        uint256 _tokenLength = _tokens.length;
        if (_amounts.length != _tokenLength) revert LengthMissMatch();
        for (uint8 i = 0; i < _tokenLength;) {
            uint256 _amount = _amounts[i];
            if (_amount == 0) revert ZeroAmount();
            if (_amount > IERC20(_tokens[i]).balanceOf(address(this))) revert ExceededBalance();
            _convertTokenToLLP(_tokens[i], _amount);
            unchecked {
                ++i;
            }
        }
        uint256 _llpBalance = LLP.balanceOf(address(this));
        LLP.safeTransfer(_to, _llpBalance);
        emit LLPConverted(_to, _llpBalance);
    }

    function swap(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut)
        external
        onlyDistributorOrOwner
    {
        if (_toToken == _fromToken) revert InvalidPath();
        if (!feeTokens[_fromToken] || !feeTokens[_toToken]) revert NotAFeeToken();
        uint256 _balanceBefore = IERC20(_toToken).balanceOf(address(this));
        IERC20(_fromToken).safeTransfer(address(pool), _amountIn);
        // self check slippage, so we send minAmountOut as 0
        pool.swap(_fromToken, _toToken, 0, address(this), abi.encode(msg.sender));
        uint256 _actualAmountOut = IERC20(_toToken).balanceOf(address(this)) - _balanceBefore;
        if (_actualAmountOut < _minAmountOut) revert Slippage();
        emit Swap(_fromToken, _toToken, _amountIn, _actualAmountOut);
    }

    /**
     * @notice operator can withdraw some tokens to manual swap or bridge to other chain's staking contract
     */
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyDistributorOrOwner {
        if (!feeTokens[_token]) revert NotAFeeToken();
        if (_to == address(0)) revert ZeroAddress();
        _safeTransferToken(_token, _to, _amount);
        emit TokenWithdrawn(_to, _amount);
    }

    function setDistributor(address _distributor) external onlyOwner {
        if (_distributor == address(0)) revert ZeroAddress();
        distributor = _distributor;
        emit DistributorSet(distributor);
    }

    function setConvertLLPTokens(address[] calldata _tokens) external onlyOwner {
        for (uint256 i = 0; i < convertLLPTokens.length;) {
            isConvertLLPTokens[convertLLPTokens[i]] = false;
            unchecked {
                ++i;
            }
        }
        for (uint256 i = 0; i < _tokens.length;) {
            if (_tokens[i] == address(0)) revert ZeroAddress();
            isConvertLLPTokens[_tokens[i]] = true;
            unchecked {
                ++i;
            }
        }
        convertLLPTokens = _tokens;
        emit ConvertLLPTokensSet(_tokens);
    }

    function setFeeToken(address _token, bool _allowed) external onlyOwner {
        if (_token == address(0)) revert ZeroAddress();
        if (_token == address(LLP)) revert NotAllowAddress();
        if (feeTokens[_token] != _allowed) {
            feeTokens[_token] = _allowed;
            emit FeeTokenSet(_token, _allowed);
        }
    }

    // =============== INTERNAL FUNCTIONS ===============
    function _checkDistributorOrOwner() internal view {
        if (msg.sender != distributor && msg.sender != owner()) revert Unauthorized();
    }

    function _convertTokenToLLP(address _token, uint256 _amount) internal {
        if (!isConvertLLPTokens[_token]) revert InvalidToken();
        if (_amount != 0) {
            IERC20(_token).safeIncreaseAllowance(address(pool), _amount);
            pool.addLiquidity(address(LLP), _token, _amount, 0, address(this));
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
    error ZeroAmount();
    error InvalidToken();
    error InvalidPath();
    error NotAFeeToken();
    error Slippage();
    error NotAllowAddress();
    error ExceededBalance();
    error LengthMissMatch();
    error Unauthorized();

    // =============== EVENTS ===============
    event DistributorSet(address indexed _distributor);
    event FeeTokenSet(address indexed _token, bool _allowed);
    event ConvertLLPTokensSet(address[] _tokens);
    event Swap(address indexed _tokenIn, address indexed _tokenOut, uint256 _amountIn, uint256 _amountOut);
    event TokenWithdrawn(address indexed _to, uint256 _amount);
    event LLPConverted(address _to, uint256 _amount);
}
