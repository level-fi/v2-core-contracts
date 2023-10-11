pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/vesting/MultiplierTracker.sol";

contract CustomMockERC20 is MockERC20 {
    IERC20 public token0;

    constructor(string memory _name, string memory _symbol, uint8 _decimals, IERC20 _token0)
        MockERC20(_name, _symbol, _decimals)
    {
        token0 = _token0;
    }

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = uint112(token0.balanceOf(address(this)));
    }
}

contract MultiplierTrackerTest is Test {
    address owner = address(bytes20("owner"));
    address alice = address(bytes20("alice"));
    address proxyAdmin = address(bytes20("proxyAdmin"));

    MockERC20 LVL;
    CustomMockERC20 LVL_USDT;

    MultiplierTracker oracle;

    function setUp() external {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(owner);
        LVL = new MockERC20("BTC", "BTC", 18);
        LVL_USDT = new CustomMockERC20("LP", "LP", 18, LVL);

        LVL.mintTo(200 ether, address(LVL_USDT));
        LVL_USDT.mintTo(100 ether, alice);

        oracle = new MultiplierTracker(address(LVL), address(LVL_USDT), 2.5e6);
        vm.stopPrank();
    }

    function test_set_updater_revert_success() external {}

    function test_update_revert_role() external {
        vm.prank(alice);
        vm.expectRevert();
        oracle.start();
    }

    function test_update_revert_time() external {
        vm.startPrank(owner);
        oracle.start();
        vm.warp(block.timestamp + 0.5 hours);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTracker.TooEarlyForUpdate.selector));
        oracle.update();
    }

    function test_update_revert_success() external {
        vm.prank(owner);
        oracle.start();
        assertEq(oracle.getVestingMultiplier(), 5e6);
        assertEq(oracle.getStakingMultiplier(), 0);
    }

    function test_get_twap_0() external {
        // start
        vm.startPrank(owner);
        oracle.start();
        vm.warp(block.timestamp + 1 days);
        oracle.update();
        vm.warp(block.timestamp + 1 days);
        oracle.update();
        vm.warp(block.timestamp + 1 days);
        oracle.update();
        vm.warp(block.timestamp + 1 days);
        oracle.update();
        vm.warp(block.timestamp + 1 days);
        oracle.update();
        vm.warp(block.timestamp + 1 days);
        oracle.update();
        vm.warp(block.timestamp + 1 days);
        oracle.update();
        assertEq(oracle.getVestingMultiplier(), 5e6);
        assertEq(oracle.getStakingMultiplier(), 5e6);
    }

    function test_get_twap_1() external {
        // start
        vm.prank(owner);
        oracle.start();

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        LVL.mintTo(200 ether, address(LVL_USDT));
        vm.prank(owner);
        oracle.update();

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        LVL.mintTo(200 ether, address(LVL_USDT));
        vm.prank(owner);
        oracle.update();

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        LVL.mintTo(200 ether, address(LVL_USDT));
        vm.prank(owner);
        oracle.update();

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        LVL.mintTo(200 ether, address(LVL_USDT));
        vm.prank(owner);
        oracle.update();

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        LVL.mintTo(200 ether, address(LVL_USDT));
        vm.prank(owner);
        oracle.update();

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        LVL.mintTo(200 ether, address(LVL_USDT));
        vm.prank(owner);
        oracle.update();

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        LVL.mintTo(200 ether, address(LVL_USDT));
        vm.prank(owner);
        oracle.update();

        assertEq(oracle.getVestingMultiplier(), 40e6);
        assertEq(oracle.getStakingMultiplier(), 22.5e6);

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        LVL.mintTo(200 ether, address(LVL_USDT));
        vm.prank(owner);
        oracle.update();

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        LVL.mintTo(200 ether, address(LVL_USDT));
        vm.prank(owner);
        oracle.update();

        assertEq(oracle.getVestingMultiplier(), 50e6);
        assertEq(oracle.getStakingMultiplier(), 22.5e6);
    }
}
