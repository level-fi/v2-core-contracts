// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TradingContest} from "src/trading-incentive/TradingContest.sol";
import {TradingIncentiveController} from "src/trading-incentive/TradingIncentiveController.sol";
import {MockLvlStaking} from "./mocks/MockLVLStaking.sol";
import {MockLevelStake} from "./mocks/MockLevelStake.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockLvlOracle} from "./mocks/MockLvlOracle.sol";
import {MockLyLevel} from "./mocks/MockLyLevel.sol";
import {ContestResult, LeaderInfoView} from "src/interfaces/ITradingContest.sol";
import "./Constants.s.sol";

contract TradingIncentiveTest is Test {
    address owner;
    address trader_1 = vm.addr(uint256(keccak256(abi.encodePacked("1"))));
    address trader_2 = vm.addr(uint256(keccak256(abi.encodePacked("2"))));
    address trader_3 = vm.addr(uint256(keccak256(abi.encodePacked("3"))));
    address poolHook = vm.addr(uint256(keccak256(abi.encodePacked("poolHook"))));
    address updater = vm.addr(uint256(keccak256(abi.encodePacked("updater"))));
    address admin = vm.addr(uint256(keccak256(abi.encodePacked("admin"))));
    address lyLevel;
    MockLvlStaking lvlStaking;
    MockLevelStake levelStake;
    TradingContest tradingContest;
    TradingIncentiveController incentiveController;
    MockLvlOracle twapOracle;

    function setUp() external {
        owner = msg.sender;
        vm.startPrank(owner);
        lyLevel = address(new MockLyLevel());
        levelStake = new MockLevelStake(Constants.LVL);
        lvlStaking = new MockLvlStaking();
        // Oracle
        twapOracle = new MockLvlOracle();

        address proxyAdmin = address(new ProxyAdmin());
        // trading contest
        TradingContest _contest = new TradingContest();
        Proxy proxy = new Proxy(address(_contest), proxyAdmin, new bytes(0));
        tradingContest = TradingContest(address(proxy));
        lvlStaking = new MockLvlStaking();
        tradingContest.initialize(poolHook);

        // trading controller
        TradingIncentiveController controllerImpl = new TradingIncentiveController();
        Proxy controllerProxy = new Proxy(address(controllerImpl), proxyAdmin, new bytes(0));

        incentiveController = TradingIncentiveController(address(controllerProxy));
        incentiveController.initialize(address(twapOracle), poolHook, address(tradingContest), address(lyLevel));
        incentiveController.setAdmin(admin);
        tradingContest.setUpdater(updater);
        tradingContest.setAdmin(admin);
        tradingContest.setController(address(incentiveController));

        vm.etch(Constants.LVL, address(new MockERC20("LVL", "LVL", 18)).code);
        deal(Constants.LVL, address(incentiveController), 100_000 ether);
        vm.stopPrank();
    }

    function test_record() external {
        vm.startPrank(owner);
        incentiveController.start(block.timestamp + 1000);
        tradingContest.start(block.timestamp + 1000);
        vm.stopPrank();

        vm.startPrank(poolHook);
        vm.warp(block.timestamp + 1000);

        incentiveController.record(1000e30);
        incentiveController.record(10000e30);
        incentiveController.record(20000e30);
        incentiveController.record(50000e30);
        incentiveController.record(100000e30);

        tradingContest.record(trader_1, 1000e30);
        tradingContest.record(trader_1, 10000e30);
        tradingContest.record(trader_2, 20000e30);
        tradingContest.record(trader_3, 50000e30);
        tradingContest.record(trader_3, 100000e30);
        vm.stopPrank();

        twapOracle.setPrice(2e12);
        vm.startPrank(admin);
        incentiveController.allocate();

        assertEq(MockLyLevel(lyLevel).totalReward(), 5_000e18);
        vm.stopPrank();
    }

    function test_update_leaders() external {
        twapOracle.setPrice(2e12);
        vm.startPrank(owner);
        incentiveController.start(block.timestamp + 1000);
        tradingContest.start(block.timestamp + 1000);
        vm.stopPrank();
        vm.warp(block.timestamp + 1000);
        vm.startPrank(address(incentiveController));
        console.log(tradingContest.currentBatch());
        // tradingContest.addExtraReward(_batchId, _rewardTokens);(30_000e18);
        vm.stopPrank();

        vm.startPrank(poolHook);
        vm.warp(block.timestamp + 1000);

        incentiveController.record(1000e30);
        incentiveController.record(10000e30);
        incentiveController.record(20000e30);
        incentiveController.record(50000e30);
        incentiveController.record(100000e30);

        tradingContest.record(trader_1, 1000e30);
        tradingContest.record(trader_1, 10000e30);
        tradingContest.record(trader_2, 20000e30);
        tradingContest.record(trader_3, 50000e30);
        tradingContest.record(trader_3, 100000e30);
        vm.stopPrank();

        vm.startPrank(admin);
        for (uint256 i = 0; i < 7; i++) {
            incentiveController.allocate();
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 1.1 days);
        vm.prank(admin);
        tradingContest.setEnableNextBatch(true);

        tradingContest.nextBatch();

        vm.startPrank(updater);

        ContestResult[] memory result = new ContestResult[](2);
        result[0] = ContestResult({trader: trader_1, index: 2, totalPoint: 100});

        result[1] = ContestResult({trader: trader_2, index: 1, totalPoint: 90});
        tradingContest.updateLeaders(1, result);

        LeaderInfoView[] memory _leaders = tradingContest.getLeaders(1);
        (uint128 rewardTokens, /* uint64 startTime */, /* uint64 endTime */, /* uint64 startVestingTime */,,,) = tradingContest.batches(1);
        console.log(rewardTokens);
        //assertEq(_leaders.length, 2);
        for (uint256 index = 0; index < _leaders.length; index++) {
            console.log(
                _leaders[index].trader, _leaders[index].index, _leaders[index].totalPoint, _leaders[index].rewardTokens
            );
        }
        vm.stopPrank();
    }

    function test_set_batch_duration() external {
        // not owner => revert
        vm.startPrank(trader_1);
        vm.expectRevert();
        tradingContest.setBatchDuration(2 days);
        vm.stopPrank();

        // switch to owner
        vm.startPrank(owner);
        // invalid value => revert
        vm.expectRevert();
        tradingContest.setBatchDuration(45 days);

        uint128 _currentBatch = tradingContest.currentBatch();
        assertEq(_currentBatch, 0);
        // success
        tradingContest.setBatchDuration(2 days);

        assertEq(tradingContest.batchDuration(), 2 days);
        vm.stopPrank();
    }

    function test_set_pool_hook() external {
        address _poolHook = vm.addr(uint256(keccak256(abi.encodePacked("_poolHook"))));
        // not owner => revert
        vm.startPrank(trader_1);
        vm.expectRevert();
        tradingContest.setPoolHook(_poolHook);
        vm.stopPrank();

        // switch to owner
        vm.startPrank(owner);

        tradingContest.setPoolHook(_poolHook);
        assertEq(_poolHook, tradingContest.poolHook());
        vm.stopPrank();
    }
}
