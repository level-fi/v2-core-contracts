//SPDX-License-Identifier: UNLCIENSED

pragma solidity >=0.8.0;

contract MockLevelNormalVesting {
    mapping(address userAddress => uint256) public reserves;

    function setReserveAmount(address _user, uint256 _amount) external {
        reserves[_user] = _amount;
    }

    function getReservedAmount(address _user) external view returns (uint256) {
        return reserves[_user];
    }
}
