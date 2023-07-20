//SPDX-License-Identifier: UNLCIENSED

pragma solidity >=0.8.0;

contract MockLvlStaking {
    mapping(address => uint256) userStaking;

    function userInfo(address _user) external view returns (uint256, int256) {
        return (userStaking[_user], 0);
    }

    function setStaking(address _user, uint256 _stakeAmount) external {
        userStaking[_user] = _stakeAmount;
    }
}
