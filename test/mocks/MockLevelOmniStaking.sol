//SPDX-License-Identifier: UNLCIENSED

pragma solidity >=0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockLevelOmniStaking {
    using SafeERC20 for IERC20;

    IERC20 token;
    mapping(address => uint256) public stakedAmounts;

    constructor(address _token) {
        require(_token != address(0));
        token = IERC20(_token);
    }

    function stake(address _to, uint256 _amount) external {
        stakedAmounts[_to] += _amount;
        token.safeTransferFrom(msg.sender, address(this), _amount);
    }
}
