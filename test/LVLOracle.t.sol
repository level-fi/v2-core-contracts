pragma solidity 0.8.18;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "src/oracle/LVLTwapOracle.sol";

contract TestLevelOracle is Test {
    address _owner;
    address constant LVL_USDT_PAIR_ADDR = 0xc11cFF8A44853A5B3F24a7F4B817E6e64fbEBA2a;
    address constant LVL_ADDR = 0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149;
    LVLTwapOracle lvlOracle;

    function setUp() external {
        _owner = msg.sender;
        vm.createSelectFork("https://rpc.ankr.com/arbitrum");
        lvlOracle = new LVLTwapOracle(LVL_ADDR, LVL_USDT_PAIR_ADDR, _owner);
        vm.prank(_owner);
        lvlOracle.update();
        vm.warp(block.timestamp + 86400);
    }

    function test_get_current_twap() external {
        uint256 _currentTWAP = lvlOracle.getCurrentTWAP();
        assertTrue(_currentTWAP > 0);
        console.log(_currentTWAP);
    }

    function test_update_twap() external {
        vm.prank(_owner);
        lvlOracle.update();
        assertTrue(lvlOracle.lastTWAP() > 0);
        console.log(lvlOracle.lastTWAP());
    }
}
