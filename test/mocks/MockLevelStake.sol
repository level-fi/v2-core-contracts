//SPDX-License-Identifier: UNLCIENSED

pragma solidity >=0.8.0;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockLevelStake {
    uint256 totalAmount;

    using SafeERC20 for IERC20;

    IERC20 public immutable LVL;
    mapping(address => uint256) userStaking;

    constructor(address _lvl) {
        LVL = IERC20(_lvl);
    }

    function stake(address /* _to */, uint256 _amount) external {
        LVL.safeTransferFrom(msg.sender, address(this), _amount);
        totalAmount += _amount;
    }

    function userInfo(address _user) external view returns (uint256, int256, uint256) {
        return (userStaking[_user], 0, 0);
    }

    function setStaking(address _user, uint256 _stakeAmount) external {
        userStaking[_user] = _stakeAmount;
    }
}
