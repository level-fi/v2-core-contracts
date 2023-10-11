pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {LevelNormalVesting} from "../src/vesting/LevelNormalVesting.sol";
import {MockLevelOmniStaking} from "./mocks/MockLevelOmniStaking.sol";
import {ILevelNormalVesting} from "../src/interfaces/ILevelNormalVesting.sol";

contract LevelNormalVestingTest is Test {
    address owner = address(bytes20("owner"));
    address alice = address(bytes20("alice"));
    address proxyAdmin = address(bytes20("proxyAdmin"));

    MockERC20 LVL;
    MockERC20 preLVL;
    MockLevelOmniStaking levelOmniStaking;
    LevelNormalVesting levelNormalVesting;

    function setUp() external {
        vm.warp(0);
        vm.startPrank(owner);
        LVL = new MockERC20("LVL", "LVL", 18);
        preLVL = new MockERC20("preLVL", "preLVL", 18);

        levelOmniStaking = new MockLevelOmniStaking(address(LVL));
        Proxy normalVestingProxy = new Proxy(
            address(new LevelNormalVesting()),
            address(proxyAdmin),
            new bytes(0)
        );
        levelNormalVesting = LevelNormalVesting(address(normalVestingProxy));
        levelNormalVesting.initialize(address(LVL), address(preLVL), address(levelOmniStaking), 10e6);

        preLVL.mintTo(10000 ether, alice);
        LVL.mintTo(10000 ether, alice);
        LVL.mintTo(10000 ether, address(levelNormalVesting));
        vm.stopPrank();
    }

    /* ========== USER FUNCTIONS ========== */
    function test_stake_revert_max_reserve() external {
        vm.startPrank(alice);
        preLVL.approve(address(levelNormalVesting), 100 ether);
        vm.expectRevert(abi.encodeWithSelector(ILevelNormalVesting.ExceededVestableAmount.selector));
        levelNormalVesting.startVesting(100 ether);
        vm.stopPrank();
    }

    function test_stake_revert_invalid_amount() external {
        vm.startPrank(alice);
        LVL.approve(address(levelOmniStaking), 1000 ether);
        levelOmniStaking.stake(alice, 1000 ether);
        vm.expectRevert(abi.encodeWithSelector(ILevelNormalVesting.ZeroAmount.selector));
        levelNormalVesting.startVesting(0 ether);
        vm.stopPrank();
    }

    function test_stake_success() external {
        vm.startPrank(alice);
        LVL.approve(address(levelOmniStaking), 1000 ether);
        levelOmniStaking.stake(alice, 1000 ether);
        preLVL.approve(address(levelNormalVesting), 100 ether);
        levelNormalVesting.startVesting(100 ether);
        vm.stopPrank();
    }

    function test_re_stake_success() external {
        vm.startPrank(alice);
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Alice stake 1000 LVL and vest 10 preLVL after 1/2 year
        {
            vm.warp(block.timestamp + (365 days / 2));
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Validate state
        {
            (uint256 vestingAmount, uint256 accVestedAmount, uint256 claimedAmount, uint256 lastVestingTime) =
                levelNormalVesting.users(alice);
            assertEq(vestingAmount, 200 ether);
            assertEq(accVestedAmount, 50 ether);
            assertEq(claimedAmount, 0 ether);
            assertEq(lastVestingTime, block.timestamp);
        }

        vm.stopPrank();
    }

    function test_stake_after_exit() external {
        vm.startPrank(alice);
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Alice exit after 1/2 year
        {
            vm.warp(block.timestamp + (365 days / 2));
            levelNormalVesting.stopVesting(alice);
        }
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Validate state after stake
        {
            (uint256 vestingAmount, uint256 accVestedAmount, uint256 claimedAmount, uint256 lastVestingTime) =
                levelNormalVesting.users(alice);
            assertEq(vestingAmount, 100 ether);
            assertEq(accVestedAmount, 0);
            assertEq(claimedAmount, 0);
            assertEq(lastVestingTime, block.timestamp);
            assertEq(LVL.balanceOf(alice), 10000 ether - 2000 ether + 50 ether);
            assertEq(preLVL.balanceOf(alice), 10000 ether - 50 ether - 100 ether);
        }
        vm.stopPrank();
    }

    function test_stake_after_claim() external {
        vm.startPrank(alice);
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Alice exit after 1/2 year
        uint256 _now = block.timestamp + (365 days / 2);
        {
            vm.warp(_now);
            levelNormalVesting.claim(alice);
        }
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Validate state after stake
        {
            (uint256 vestingAmount, uint256 accVestedAmount, uint256 claimedAmount, uint256 lastVestingTime) =
                levelNormalVesting.users(alice);
            assertEq(vestingAmount, 200 ether);
            assertEq(accVestedAmount, 50 ether);
            assertEq(claimedAmount, 50 ether);
            assertEq(lastVestingTime, _now);
            assertEq(LVL.balanceOf(alice), 10000 ether - 2000 ether + 50 ether);
            assertEq(preLVL.balanceOf(alice), 10000 ether - 100 ether - 100 ether);
        }
        vm.stopPrank();
    }

    function test_calc_claimable() external {
        uint256 _now = block.timestamp;
        vm.startPrank(alice);
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Alice stake 1000 LVL and vest 10 preLVL after 1/2 year
        {
            vm.warp(_now + (365 days / 2));
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Validate state
        (uint256 vestingAmount, uint256 accVestedAmount, uint256 claimedAmount, uint256 lastVestingTime) =
            levelNormalVesting.users(alice);
        {
            assertEq(vestingAmount, 200 ether);
            assertEq(accVestedAmount, 50 ether);
            assertEq(claimedAmount, 0 ether);
        }
        // Check claimable reward after 1 year
        {
            vm.warp(_now + 365 days);
            (vestingAmount, accVestedAmount, claimedAmount, lastVestingTime) = levelNormalVesting.users(alice);
            assertEq(vestingAmount, 200 ether);
            assertEq(accVestedAmount, 50 ether);
            assertEq(claimedAmount, 0 ether);
            assertEq(levelNormalVesting.claimable(alice), 50 ether + 100 ether);
        }
        // Check claimable reward after 2 year
        vm.warp(_now + 365 days * 2);
        {
            (vestingAmount, accVestedAmount, claimedAmount, lastVestingTime) = levelNormalVesting.users(alice);
            assertEq(vestingAmount, 200 ether);
            assertEq(accVestedAmount, 50 ether);
            assertEq(levelNormalVesting.claimable(alice), 200 ether);
            assertEq(claimedAmount, 0 ether);
        }
        // Alice claim
        {
            levelNormalVesting.claim(alice);
            (vestingAmount, accVestedAmount, claimedAmount, lastVestingTime) = levelNormalVesting.users(alice);
            assertEq(vestingAmount, 200 ether);
            assertEq(accVestedAmount, 200 ether);
            assertEq(levelNormalVesting.claimable(alice), 0);
            assertEq(claimedAmount, 200 ether);
        }
        // Alice exit
        {
            levelNormalVesting.stopVesting(alice);
            (vestingAmount, accVestedAmount, claimedAmount, lastVestingTime) = levelNormalVesting.users(alice);
            assertEq(vestingAmount, 0);
            assertEq(accVestedAmount, 0);
            assertEq(levelNormalVesting.claimable(alice), 0);
            assertEq(claimedAmount, 0);
        }

        vm.stopPrank();
    }

    function test_exit_revert_because_not_stake_first() external {
        vm.expectRevert(abi.encodeWithSelector(ILevelNormalVesting.ZeroVestingAmount.selector));
        levelNormalVesting.stopVesting(alice);
    }

    function test_exit_revert_invalid_address() external {
        vm.expectRevert(abi.encodeWithSelector(ILevelNormalVesting.ZeroAddress.selector));
        levelNormalVesting.stopVesting(address(0));
    }

    function test_exit_success() external {
        vm.startPrank(alice);
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Alice exit after 1/2 year
        {
            vm.warp(block.timestamp + (365 days / 2));
            levelNormalVesting.stopVesting(alice);
        }
        // Validate state after exit
        {
            (uint256 vestingAmount, uint256 accVestedAmount, uint256 claimedAmount, uint256 lastVestingTime) =
                levelNormalVesting.users(alice);
            assertEq(vestingAmount, 0);
            assertEq(accVestedAmount, 0);
            assertEq(claimedAmount, 0);
            assertEq(lastVestingTime, 0);
            assertEq(LVL.balanceOf(alice), 10000 ether - 1000 ether + 50 ether);
            assertEq(preLVL.balanceOf(alice), 10000 ether - 50 ether);
        }
        vm.stopPrank();
    }

    function test_exit_after_claim_success() external {
        vm.startPrank(alice);
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 1000 ether);
            levelOmniStaking.stake(alice, 1000 ether);
            preLVL.approve(address(levelNormalVesting), 100 ether);
            levelNormalVesting.startVesting(100 ether);
        }
        // Alice exit after 1/2 year
        {
            vm.warp(block.timestamp + (365 days / 2));
            assertEq(LVL.balanceOf(alice), 10000 ether - 1000 ether);
            levelNormalVesting.claim(alice);
            levelNormalVesting.stopVesting(alice);
        }
        // Validate state after exit
        {
            (uint256 vestingAmount, uint256 accVestedAmount, uint256 claimedAmount, uint256 lastVestingTime) =
                levelNormalVesting.users(alice);
            assertEq(vestingAmount, 0);
            assertEq(accVestedAmount, 0);
            assertEq(claimedAmount, 0);
            assertEq(lastVestingTime, 0);
            assertEq(LVL.balanceOf(alice), 10000 ether - 1000 ether + 50 ether);
            assertEq(preLVL.balanceOf(alice), 10000 ether - 50 ether);
        }
        vm.stopPrank();
    }

    function test_claim_revert_invalid_address() external {
        vm.startPrank(alice);
        // Alice stake 1000 LVL and vest 10 preLVL
        LVL.approve(address(levelOmniStaking), 1000 ether);
        levelOmniStaking.stake(alice, 1000 ether);
        preLVL.approve(address(levelNormalVesting), 100 ether);
        levelNormalVesting.startVesting(100 ether);
        // Alice exit after 1/2 year
        vm.warp(block.timestamp + (365 days / 2));
        vm.expectRevert(abi.encodeWithSelector(ILevelNormalVesting.ZeroAddress.selector));
        levelNormalVesting.claim(address(0));
        vm.stopPrank();
    }

    function test_claim_success() external {
        vm.startPrank(alice);
        uint256 _now = block.timestamp;
        // Alice stake 1000 LVL and vest 10 preLVL
        LVL.approve(address(levelOmniStaking), 1000 ether);
        levelOmniStaking.stake(alice, 1000 ether);
        preLVL.approve(address(levelNormalVesting), 100 ether);
        levelNormalVesting.startVesting(100 ether);
        // Alice exit after 1/2 year
        vm.warp(block.timestamp + (365 days / 2));
        levelNormalVesting.claim(alice);
        // Validate state after claim
        (uint256 vestingAmount, uint256 accVestedAmount, uint256 claimedAmount, uint256 lastVestingTime) =
            levelNormalVesting.users(alice);
        assertEq(vestingAmount, 100 ether);
        assertEq(accVestedAmount, 50 ether);
        assertEq(claimedAmount, 50 ether);
        assertEq(LVL.balanceOf(alice), 10000 ether - 1000 ether + 50 ether);
        assertEq(preLVL.balanceOf(alice), 10000 ether - 100 ether);
        vm.stopPrank();
    }

    function test_claim_but_not_have_reward_success() external {
        levelNormalVesting.claim(alice);
        assertEq(LVL.balanceOf(alice), 10000 ether);
        assertEq(preLVL.balanceOf(alice), 10000 ether);
    }

    // // =============== RESTRICTED ===============
    function test_set_reserve_rate_revert_owner() external {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        levelNormalVesting.setReserveRate(10e6);
    }

    function test_set_reserve_rate_revert_invalid_mount() external {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(ILevelNormalVesting.ReserveRateTooLow.selector));
        levelNormalVesting.setReserveRate(0);
        vm.expectRevert(abi.encodeWithSelector(ILevelNormalVesting.ReserveRateTooHigh.selector));
        levelNormalVesting.setReserveRate(1_000_000e6);
    }

    function test_set_reserve_rate_success() external {
        vm.prank(owner);
        levelNormalVesting.setReserveRate(10e6);
    }

    function test_recover_fund_revert_owner() external {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        levelNormalVesting.recoverFund(alice, 100 ether);
    }

    function test_recover_fund_revert_invalid_address() external {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(ILevelNormalVesting.ZeroAddress.selector));
        levelNormalVesting.recoverFund(address(0), 100 ether);
    }

    function test_recover_fund_success() external {
        vm.prank(owner);
        levelNormalVesting.recoverFund(alice, 100 ether);
    }

    function test_decrease_reserve_rate_success() external {
        vm.startPrank(alice);
        // Alice stake 1000 LVL and vest 10 preLVL
        LVL.approve(address(levelOmniStaking), 1000 ether);
        levelOmniStaking.stake(alice, 1000 ether);
        preLVL.approve(address(levelNormalVesting), 100 ether);
        levelNormalVesting.startVesting(100 ether);
        vm.stopPrank();
    }

    function test_get_reserve_amount() external {
        vm.startPrank(alice);
        uint256 reserveAmount = levelNormalVesting.getReservedAmount(alice);
        assertEq(reserveAmount, 0);
        LVL.approve(address(levelOmniStaking), 1500 ether);
        levelOmniStaking.stake(alice, 1500 ether);
        preLVL.approve(address(levelNormalVesting), 1000 ether);
        levelNormalVesting.startVesting(100 ether);
        reserveAmount = levelNormalVesting.getReservedAmount(alice);
        assertEq(reserveAmount, 1000 ether);
        vm.warp(block.timestamp + (365 days / 2));
        reserveAmount = levelNormalVesting.getReservedAmount(alice);
        assertEq(reserveAmount, 1000 ether);
        levelNormalVesting.startVesting(50 ether);
        reserveAmount = levelNormalVesting.getReservedAmount(alice);
        assertEq(reserveAmount, 1500 ether);
        vm.expectRevert(abi.encodeWithSelector(ILevelNormalVesting.ExceededVestableAmount.selector));
        levelNormalVesting.startVesting(1 ether);
        LVL.approve(address(levelOmniStaking), 10 ether);
        levelOmniStaking.stake(alice, 10 ether);
        levelNormalVesting.startVesting(1 ether);
        reserveAmount = levelNormalVesting.getReservedAmount(alice);
        assertEq(reserveAmount, 1510 ether);
        vm.stopPrank();
    }

    function test_rounding() external {
        vm.startPrank(alice);
        uint256 _now = block.timestamp;
        // Verify state and balance before interact
        {
            assertEq(LVL.balanceOf(address(levelNormalVesting)), 10000 ether);
            assertEq(preLVL.balanceOf(address(levelNormalVesting)), 0);
        }
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 10);
            levelOmniStaking.stake(alice, 10);
            preLVL.approve(address(levelNormalVesting), 1);
            levelNormalVesting.startVesting(1);
        }
        // Alice exit after 1/3 year
        {
            vm.warp(block.timestamp + (365 days / 3));
            levelNormalVesting.claim(alice); // reward < 1
        }
        // Alice exit after 1/2 year
        {
            vm.warp(block.timestamp + (365 days / 2));
            levelNormalVesting.claim(alice); // reward < 1
        }
        // Alice exit after 1 year
        {
            vm.warp(block.timestamp + (365 days));
            levelNormalVesting.stopVesting(address(alice));
        }
        // Verify state and balance
        {
            (uint256 vestingAmount, uint256 accVestedAmount, uint256 claimedAmount, uint256 lastVestingTime) =
                levelNormalVesting.users(alice);
            assertEq(LVL.balanceOf(alice), 10000 ether - 10 + 1);
            assertEq(preLVL.balanceOf(alice), 10000 ether - 1);
            assertEq(LVL.balanceOf(address(levelNormalVesting)), 10000 ether - 1);
            assertEq(preLVL.balanceOf(address(levelNormalVesting)), 0);
        }
        vm.stopPrank();
    }

    function test_rounding_2() external {
        vm.startPrank(alice);
        uint256 _now = block.timestamp;
        // Verify state and balance before interact
        {
            assertEq(LVL.balanceOf(address(levelNormalVesting)), 10000 ether);
            assertEq(preLVL.balanceOf(address(levelNormalVesting)), 0);
        }
        // Alice stake 1000 LVL and vest 10 preLVL
        {
            LVL.approve(address(levelOmniStaking), 30);
            levelOmniStaking.stake(alice, 30);
            preLVL.approve(address(levelNormalVesting), 3);
            levelNormalVesting.startVesting(3);
        }
        // Alice exit after 1/6 year
        {
            vm.warp(block.timestamp + (365 days / 6));
            levelNormalVesting.claim(alice); // reward < 1
        }
        // Alice exit after 1/4 year
        {
            vm.warp(block.timestamp + (365 days / 4));
            levelNormalVesting.claim(alice);
        }
        // Alice exit after 1/3 year
        {
            vm.warp(block.timestamp + (365 days / 3));
            levelNormalVesting.claim(alice);
        }
        // Alice exit after 1/2 year
        {
            vm.warp(block.timestamp + (365 days / 2));
            levelNormalVesting.claim(alice);
        }
        // Alice exit after 1 year
        {
            vm.warp(block.timestamp + (365 days));
            levelNormalVesting.stopVesting(address(alice));
        }
        // Verify state and balance after interact
        {
            (uint256 vestingAmount, uint256 accVestedAmount, uint256 claimedAmount, uint256 lastVestingTime) =
                levelNormalVesting.users(alice);
            assertEq(LVL.balanceOf(alice), 10000 ether - 30 + 3);
            assertEq(preLVL.balanceOf(alice), 10000 ether - 3);
            assertEq(LVL.balanceOf(address(levelNormalVesting)), 10000 ether - 3);
            assertEq(preLVL.balanceOf(address(levelNormalVesting)), 0);
        }
        vm.stopPrank();
    }
}
