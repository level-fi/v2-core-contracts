// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @notice hold LVL token to used in auction and receive token commited by user when auction success
 *  The pay token then converted to protocol owned LP
 */
contract AuctionTreasury is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant RATIO_PRECISION = 1000;

    IERC20 public constant LVL = IERC20(0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149);
    IERC20 public constant USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    /// @notice LVLAuctionFactory can request transfer protocol tokens from this contract
    address public LVLAuctionFactory;
    /// @notice address allowed to call distribute bid token
    address public admin;
    /// @notice hold USDT to be converted to LVL/USDT LP
    address public cashTreasury;
    /// @notice hold USDT to deposit to LevelPool and become LLP
    address public llpReserve;
    /// @notice part of token to be sent to treasury to convert to LVL/USDT LP
    uint256 public usdtToCashTreasuryRatio;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _cashTreasury, address _llpReserve) external initializer {
        __Ownable_init();
        require(_cashTreasury != address(0), "Invalid address");
        require(_llpReserve != address(0), "Invalid address");
        cashTreasury = _cashTreasury;
        llpReserve = _llpReserve;
        usdtToCashTreasuryRatio = 750;
    }

    /**
     * @notice request by authorized auction contract factory when creating a new auction
     */
    function transferLVL(address _for, uint256 _amount) external {
        require(msg.sender == LVLAuctionFactory, "only LVLAuctionFactory");
        LVL.safeTransfer(_for, _amount);
        emit LVLGranted(_for, _amount);
    }

    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Invalid address");
        admin = _admin;
        emit AdminSet(_admin);
    }

    function setLVLAuctionFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid address");
        LVLAuctionFactory = _factory;
        emit LVLAuctionFactorySet(_factory);
    }

    /**
     * @notice distribute USDT to each reserves
     */
    function distribute() external {
        require(msg.sender == admin || msg.sender == owner(), "Only Owner or Admin can operate");
        uint256 _usdtBalance = USDT.balanceOf(address(this));
        uint256 _amountToTreasury = (_usdtBalance * usdtToCashTreasuryRatio) / RATIO_PRECISION;
        uint256 _amountToLP = _usdtBalance - _amountToTreasury;

        // 1. split to Treasury
        if (_amountToTreasury > 0) {
            require(cashTreasury != address(0), "Invalid address");
            USDT.safeTransfer(cashTreasury, _amountToTreasury);
        }

        // 2. convert to LP
        if (_amountToLP > 0) {
            require(llpReserve != address(0), "Invalid address");
            USDT.safeTransfer(llpReserve, _amountToLP);
        }
    }

    function recoverFund(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
        emit FundRecovered(_token, _to, _amount);
    }

    /* ========== EVENTS ========== */
    event AdminSet(address _admin);
    event LVLGranted(address _for, uint256 _amount);
    event LGOGranted(address _for, uint256 _amount);
    event LVLAuctionFactorySet(address _factory);
    event LGOAuctionFactorySet(address _factory);
    event FundRecovered(address indexed _token, address _to, uint256 _amount);
    event FundWithdrawn(address indexed _token, address _to, uint256 _amount);
}
