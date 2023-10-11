// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILevelOmniStakingReserve {
    function convertTokenToLLP(address _to) external;
    function convertTokenToLLP(address[] calldata _tokens, uint256[] calldata _amounts, address _to) external;
}
