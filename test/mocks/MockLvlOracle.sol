// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

/// @title LP Token
/// @author YAPP
/// @notice User will receive LP Token when deposit their token to protocol; and it can be redeem to receive
/// any token of their choice
contract MockLvlOracle {
    uint256 public price;

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function update() external {}

    function lastTWAP() external view returns (uint256) {
        return price;
    }

    function getCurrentTWAP() external view returns (uint256) {
        return price;
    }
}
