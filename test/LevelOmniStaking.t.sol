pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/staking/LevelOmniStaking.sol";
import {WETH9} from "./mocks/WETH.sol";
import {ETHUnwrapper} from "./mocks/ETHUnwrapper.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {ILPToken} from "../src/interfaces/ILPToken.sol";

contract LevelOmniStakingTest is Test {
    address owner = address(bytes20("owner"));
    address distributor = address(bytes20("distributor"));
    address alice = address(bytes20("alice"));
    address bob = address(bytes20("bob"));
    address lvlStakingV1 = 0x08A12FFedf49fa5f149C73B07E31f99249e40869;
    address proxyAdmin = address(bytes20("proxyAdmin"));

    MockERC20 LVL;
    ILPToken LLP;
    MockERC20 BTC;
    MockERC20 USDT;
    WETH9 weth;

    ETHUnwrapper ethUnwrapper;
    MockPool pool;

    LevelOmniStaking lvlStaking;

    address[] convertLLPTokens = new address[](2);

    function setUp() external {
        vm.warp(0);
        vm.startPrank(owner);
        LVL = new MockERC20("LVL", "LVL", 18);
        BTC = new MockERC20("BTC", "BTC", 18);
        USDT = new MockERC20("USDT", "USDT", 18);
        weth = new WETH9();

        LVL.mintTo(200 ether, alice);

        ethUnwrapper = new ETHUnwrapper(address(weth));
        pool = new MockPool();
        LLP = pool.lpToken();

        Proxy omniStakingProxy = new Proxy(
            address(new LevelOmniStaking()),
            address(proxyAdmin),
            new bytes(0)
        );
        lvlStaking = LevelOmniStaking(address(omniStakingProxy));
        lvlStaking.initialize(
            address(pool), address(LVL), address(LLP), address(weth), address(ethUnwrapper), block.timestamp + 1 days
        );

        lvlStaking.setEpochDuration(1 days);

        convertLLPTokens[0] = address(weth);
        convertLLPTokens[1] = address(BTC);
        lvlStaking.setConvertLLPTokens(convertLLPTokens);

        lvlStaking.setClaimableToken(address(BTC), true);
        lvlStaking.setFeeToken(address(BTC), true);
        vm.stopPrank();
    }

    /* ========== USER FUNCTIONS ========== */

    /* Stake */

    function test_stake_revert_invalid_amount() external {
        vm.warp(1 days);

        vm.startPrank(alice);
        vm.expectRevert("Invalid amount");
        lvlStaking.stake(alice, 0);
        vm.expectRevert("ERC20: insufficient allowance");
        lvlStaking.stake(alice, 200 ether);
        LVL.approve(address(lvlStaking), 400 ether);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        lvlStaking.stake(alice, 400 ether);
        vm.stopPrank();
    }

    function test_stake_revert_invalid_address() external {
        vm.warp(1 days);

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 100 ether);
        vm.expectRevert("Invalid address");
        lvlStaking.stake(address(0), 100 ether);
        vm.stopPrank();
    }

    function test_stake_simple_with_tax() external {
        vm.warp(1 days);

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        assertEq(LVL.balanceOf(alice), 100 ether);
        assertEq(lvlStaking.stakedAmounts(alice), 99.6 ether);
        vm.stopPrank();
    }

    function test_stake_to_another_address_success() external {
        vm.warp(1 days);

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(bob, 100 ether);
        assertEq(lvlStaking.stakedAmounts(alice), 0);
        assertEq(lvlStaking.stakedAmounts(bob), 99.6 ether);
        assertEq(LVL.balanceOf(alice), 100 ether);
        lvlStaking.stake(bob, 100 ether);
        assertEq(lvlStaking.stakedAmounts(alice), 0);
        assertEq(lvlStaking.stakedAmounts(bob), 99.6 ether * 2);
        assertEq(LVL.balanceOf(alice), 0 ether);
        vm.stopPrank();
    }

    function test_stake_2_epoch() external {
        vm.startPrank(owner);
        uint256 start = block.timestamp + 1 days;
        vm.stopPrank();
        // 1: Alice stake 100 ether when epoch start
        vm.warp(1 days);
        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        vm.stopPrank();
        vm.warp(start + 1 days);
        // 2: Owner next epoch
        vm.startPrank(owner);
        lvlStaking.setEnableNextEpoch(true);
        lvlStaking.nextEpoch();
        vm.stopPrank();
        // 3: Alice stake 100 ether when epoch 1
        vm.warp(start + 1 days + 1 hours);
        vm.prank(alice);
        lvlStaking.stake(alice, 100 ether);
        (,, uint256 accShare,) = lvlStaking.users(alice, 1);
        assertTrue(accShare > 0);
    }

    function test_update_total_share() external {
        vm.startPrank(owner);
        uint256 start = block.timestamp + 1 days;
        LVL.mintTo(100 ether, bob);
        vm.stopPrank();
        // 1: Alice stake 10 ether when epoch 0 start
        {
            vm.warp(1 days);
            vm.startPrank(alice);
            LVL.approve(address(lvlStaking), 200 ether);
            lvlStaking.stake(alice, 10 ether);
            vm.stopPrank();
            vm.startPrank(bob);
            LVL.approve(address(lvlStaking), 200 ether);
            lvlStaking.stake(bob, 10 ether);
            vm.stopPrank();
            vm.warp(start + 1 days);
        }
        // Alice and bob stake when epoch ended but owner miss next epoch
        {
            vm.warp(start + 1 days + 1 hours);
            vm.prank(alice);
            lvlStaking.stake(alice, 10 ether);
            vm.prank(bob);
            lvlStaking.stake(bob, 10 ether);
            vm.warp(start + 1 days + 2 hours);
            vm.prank(alice);
            lvlStaking.stake(alice, 10 ether);
            vm.prank(bob);
            lvlStaking.stake(bob, 10 ether);
        }
        // Validate share in epoch 0
        (,, uint256 aliceAccShare,) = lvlStaking.users(alice, 0);
        (,, uint256 bobAccShare,) = lvlStaking.users(bob, 0);
        (,,, uint256 totalShare,,) = lvlStaking.epochs(0);
        assertEq(aliceAccShare + bobAccShare, totalShare);
        assertEq(aliceAccShare, bobAccShare);
        // Owner next epoch
        {
            vm.warp(start + 1 days + 3 hours);
            vm.startPrank(owner);
            lvlStaking.setEnableNextEpoch(true);
            lvlStaking.nextEpoch();
            vm.stopPrank();
        }
        // Revalidate share in epoch 0
        {
            (,, aliceAccShare,) = lvlStaking.users(alice, 0);
            (,, bobAccShare,) = lvlStaking.users(bob, 0);
            (,,, totalShare,,) = lvlStaking.epochs(0);
            uint256 estAliceShare = aliceAccShare + (1 hours * 30 ether * 996 / 1000);
            uint256 estBobShare = bobAccShare + (1 hours * 30 ether * 996 / 1000);
            assertEq(estAliceShare + estBobShare, totalShare);
            assertEq(estAliceShare, estBobShare);
        }
        // Alice and bob stake in epoch 1
        {
            vm.prank(alice);
            lvlStaking.stake(alice, 10 ether);
            vm.prank(bob);
            lvlStaking.stake(bob, 10 ether);
        }
        // Validate share in epoch 1 and expect total share = 0
        {
            (,, aliceAccShare,) = lvlStaking.users(alice, 1);
            (,, bobAccShare,) = lvlStaking.users(bob, 1);
            (,,, totalShare,,) = lvlStaking.epochs(1);
            assertEq(aliceAccShare, 0);
            assertEq(bobAccShare, 0);
            assertEq(totalShare, 0);
        }
        // Alice and bob stake after epoch 1 start 2 hours
        {
            vm.warp(start + 1 days + 5 hours);
            vm.prank(alice);
            lvlStaking.stake(alice, 10 ether);
            vm.prank(bob);
            lvlStaking.stake(bob, 10 ether);
        }
        // Revalidate share in epoch 1 and expect total share > 0
        {
            (,, aliceAccShare,) = lvlStaking.users(alice, 1);
            (,, bobAccShare,) = lvlStaking.users(bob, 1);
            (,,, totalShare,,) = lvlStaking.epochs(1);
            assertEq(aliceAccShare, bobAccShare);
            assertEq(aliceAccShare + bobAccShare, totalShare);
        }
    }

    /* Unstake */
    function test_unstake_revert_invalid_amount() external {
        vm.warp(1 days);

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        vm.expectRevert("Insufficient staked amount");
        lvlStaking.unstake(alice, 100 ether);
        vm.stopPrank();
    }

    function test_unstake_revert_invalid_address() external {
        vm.warp(1 days);

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        vm.expectRevert("Invalid address");
        lvlStaking.unstake(address(0), 99.6 ether);
        vm.stopPrank();
    }

    function test_unstake_success() external {
        vm.warp(1 days);

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        assertEq(LVL.balanceOf(alice), 100 ether);
        lvlStaking.unstake(alice, 99.6 ether);
        assertEq(LVL.balanceOf(alice), 199.6 ether);
        vm.stopPrank();
    }

    function test_unstake_to_another_address_success() external {
        vm.warp(1 days);

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        assertEq(LVL.balanceOf(alice), 100 ether);
        lvlStaking.unstake(bob, 99.6 ether);
        assertEq(LVL.balanceOf(alice), 100 ether);
        assertEq(LVL.balanceOf(bob), 99.6 ether);
        vm.stopPrank();
    }

    /* Allocate reward */
    function test_allocate_reward_revert_permission() external {
        vm.warp(1 days);
        vm.startPrank(owner);
        BTC.mintTo(100 ether, address(lvlStaking)); // mock withdraw fee
        vm.stopPrank();

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);

        vm.warp(2 days);
        vm.expectRevert("Caller is not the distributor or owner");
        lvlStaking.allocateReward(0);
    }

    function test_allocate_reward_revert_epoch_not_end() external {
        vm.warp(1 days);
        vm.startPrank(owner);
        BTC.mintTo(100 ether, address(lvlStaking)); // mock withdraw fee
        vm.stopPrank();

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        vm.stopPrank();

        vm.warp(2 days);
        vm.startPrank(owner);
        vm.expectRevert("Epoch not ended");
        lvlStaking.allocateReward(0);
    }

    function test_allocate_reward_revert_invalid_reward() external {
        vm.warp(1 days);

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        vm.stopPrank();

        vm.warp(2 days);
        vm.startPrank(owner);
        lvlStaking.setEnableNextEpoch(true);
        lvlStaking.nextEpoch();
        vm.expectRevert("Reward = 0");
        lvlStaking.allocateReward(0);
    }

    function test_allocate_reward_success() external {
        vm.warp(1 days);
        vm.startPrank(owner);
        BTC.mintTo(100 ether, address(lvlStaking)); // mock withdraw fee
        vm.stopPrank();

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        vm.stopPrank();

        vm.warp(2 days);
        vm.startPrank(owner);
        lvlStaking.setEnableNextEpoch(true);
        lvlStaking.nextEpoch();
        lvlStaking.allocateReward(0);
    }

    function test_claim_reward_with_amount_success() external {
        vm.warp(1 days);
        vm.startPrank(owner);
        BTC.mintTo(100 ether, address(lvlStaking)); // mock withdraw fee
        vm.stopPrank();

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        vm.stopPrank();

        vm.warp(2 days);
        vm.startPrank(owner);
        lvlStaking.setEnableNextEpoch(true);
        lvlStaking.nextEpoch();
        LVL.mint(100 ether);
        LVL.transfer(address(lvlStaking), 100 ether);
        uint256[] memory convertLLPAmounts = new uint256[](2);
        convertLLPAmounts[0] = weth.balanceOf(address(lvlStaking));
        convertLLPAmounts[1] = BTC.balanceOf(address(lvlStaking));
        lvlStaking.allocateReward(0, convertLLPTokens, convertLLPAmounts);
        vm.stopPrank();

        vm.startPrank(alice);
        assertEq(BTC.balanceOf(alice), 0 ether);
        vm.expectRevert("!claimableTokens");
        lvlStaking.claimRewardsToSingleToken(0, alice, address(0), 0);
        lvlStaking.claimRewardsToSingleToken(0, alice, address(BTC), 0);
        assertEq(BTC.balanceOf(alice), 100 ether);
    }

    function test_claim_reward_to_token_success() external {
        vm.warp(1 days);
        vm.startPrank(owner);
        BTC.mintTo(100 ether, address(lvlStaking)); // mock withdraw fee
        vm.stopPrank();

        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        lvlStaking.stake(alice, 100 ether);
        vm.stopPrank();

        vm.warp(2 days);
        vm.startPrank(owner);
        lvlStaking.setEnableNextEpoch(true);
        lvlStaking.nextEpoch();
        lvlStaking.allocateReward(0);
        vm.stopPrank();

        vm.startPrank(alice);
        assertEq(BTC.balanceOf(alice), 0 ether);
        vm.expectRevert("!claimableTokens");
        lvlStaking.claimRewardsToSingleToken(0, alice, address(0), 0);
        lvlStaking.claimRewardsToSingleToken(0, alice, address(BTC), 0);
        assertEq(BTC.balanceOf(alice), 100 ether);
    }

    /* Snapshot with Binary search | private function */
    function test_get_snapshot_balance() external {
        vm.prank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        vm.prank(bob);
        LVL.approve(address(lvlStaking), 200 ether);

        vm.warp(1 days);
        vm.startPrank(owner);
        LVL.mintTo(200 ether, bob);
        lvlStaking.setEnableNextEpoch(true);
        vm.stopPrank();

        uint256 snapshotBalance;
        // Epoch 0 alice stake 10 ether => 9.96 ether
        {
            vm.prank(alice);
            lvlStaking.stake(alice, 10 ether);
            snapshotBalance = lvlStaking.getStakedAmountByEpoch(0, alice);
            assertEq(snapshotBalance, 9.96 ether);
        }
        // Epoch 0 alice unstake 5 ether => 4.96 ether
        {
            vm.warp(1 days + 1 hours);
            vm.prank(alice);
            lvlStaking.unstake(alice, 5 ether);
            snapshotBalance = lvlStaking.getStakedAmountByEpoch(0, alice);
            assertEq(snapshotBalance, 4.96 ether);
            snapshotBalance = lvlStaking.getStakedAmountByEpoch(0, bob);
            assertEq(snapshotBalance, 0);
        }
        // Next epoch to epoch 1
        {
            vm.prank(owner);
            vm.warp(2 days);
            lvlStaking.nextEpoch();
        }
        // Epoch 1 bob stake 5 ether => 9.96 ether
        {
            vm.prank(bob);
            lvlStaking.stake(bob, 10 ether);
            snapshotBalance = lvlStaking.getStakedAmountByEpoch(1, bob);
            assertEq(snapshotBalance, 9.96 ether);
            snapshotBalance = lvlStaking.getStakedAmountByEpoch(1, alice);
            assertEq(snapshotBalance, 4.96 ether);
        }
        // Next epoch to epoch 2
        {
            vm.warp(3 days);
            lvlStaking.nextEpoch();
        }
        // Next epoch to epoch 3
        {
            vm.warp(4 days);
            lvlStaking.nextEpoch();
            snapshotBalance = lvlStaking.getStakedAmountByEpoch(3, bob);
            assertEq(snapshotBalance, 9.96 ether);
            snapshotBalance = lvlStaking.getStakedAmountByEpoch(3, alice);
            assertEq(snapshotBalance, 4.96 ether);
            vm.prank(alice);
            lvlStaking.unstake(alice, 2.96 ether);
            snapshotBalance = lvlStaking.getStakedAmountByEpoch(3, bob);
            assertEq(snapshotBalance, 9.96 ether);
            snapshotBalance = lvlStaking.getStakedAmountByEpoch(3, alice);
            assertEq(snapshotBalance, 2 ether);
        }
        // Next to epoch 5
        {
            vm.warp(5 days);
            lvlStaking.nextEpoch();
            vm.warp(6 days);
            lvlStaking.nextEpoch();
            vm.prank(alice);
            lvlStaking.unstake(alice, 2 ether);
        }
        assertEq(lvlStaking.getStakedAmountByEpoch(6, alice), 0 ether);
        assertEq(lvlStaking.getStakedAmountByEpoch(5, alice), 0 ether);
        assertEq(lvlStaking.getStakedAmountByEpoch(4, alice), 2 ether);
        assertEq(lvlStaking.getStakedAmountByEpoch(3, alice), 2 ether);
        assertEq(lvlStaking.getStakedAmountByEpoch(2, alice), 4.96 ether);
        assertEq(lvlStaking.getStakedAmountByEpoch(1, alice), 4.96 ether);
        assertEq(lvlStaking.getStakedAmountByEpoch(0, alice), 4.96 ether);
        uint256 gas;

        for (uint256 i = 0; i < 7; i++) {
            gas = gasleft();
            lvlStaking.getStakedAmountByEpoch(i, alice);
            console.log("gas", i, gas - gasleft());
        }
    }

    /* Claim reward with multiple time */
    function test_claim_reward() external {
        vm.prank(alice);
        LVL.approve(address(lvlStaking), 200 ether);

        vm.prank(bob);
        LVL.approve(address(lvlStaking), 100 ether);

        uint256 rewardPerEpoch = 10 ether;

        vm.warp(1 days);
        vm.startPrank(owner);
        LVL.mintTo(200 ether, bob);
        LLP.approve(address(lvlStaking), 100 ether);
        lvlStaking.setEnableNextEpoch(true);
        vm.stopPrank();

        assertEq(LLP.balanceOf(alice), 0);
        // Epoch 0
        {
            vm.prank(alice);
            lvlStaking.stake(alice, 10 ether);
            vm.warp(1 days + 1 hours);
            vm.prank(alice);
            lvlStaking.unstake(alice, 5 ether);
        }
        // Epoch 1
        {
            vm.startPrank(owner);
            vm.warp(2 days);
            BTC.mintTo(rewardPerEpoch, address(lvlStaking)); // mock withdraw fee
            lvlStaking.nextEpoch();
            lvlStaking.allocateReward(0);
            vm.stopPrank();
        }
        // Epoch 2
        {
            vm.startPrank(owner);
            vm.warp(3 days);
            lvlStaking.nextEpoch();
            BTC.mintTo(rewardPerEpoch, address(lvlStaking)); // mock withdraw fee
            lvlStaking.allocateReward(1);
            vm.stopPrank();
            vm.warp(3 days + 12 hours);
            vm.prank(bob);
            lvlStaking.stake(bob, 10 ether);
            vm.prank(bob);
            lvlStaking.unstake(bob, 5 ether);
        }
        // Epoch 3
        {
            vm.startPrank(owner);
            vm.warp(4 days);
            lvlStaking.nextEpoch();
            BTC.mintTo(rewardPerEpoch, address(lvlStaking)); // mock withdraw fee
            lvlStaking.allocateReward(2);
            vm.stopPrank();
        }
        // Epoch 4
        {
            vm.startPrank(owner);
            vm.warp(5 days);
            lvlStaking.nextEpoch();
            BTC.mintTo(rewardPerEpoch, address(lvlStaking)); // mock withdraw fee
            lvlStaking.allocateReward(3);
            vm.stopPrank();
        }

        vm.startPrank(alice);
        lvlStaking.claimRewards(0, alice);
        uint256 aliceReward = 10 ether;
        assertEq(LLP.balanceOf(alice), aliceReward);
        lvlStaking.claimRewards(1, alice);
        aliceReward += 10 ether;
        assertEq(LLP.balanceOf(alice), aliceReward);
        lvlStaking.claimRewards(2, alice);
        aliceReward += (rewardPerEpoch * 2 / 3);
        assertEq(LLP.balanceOf(alice), aliceReward);
        lvlStaking.claimRewards(3, alice);
        aliceReward += rewardPerEpoch / 2;
        assertEq(LLP.balanceOf(alice), aliceReward);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 bobReward = (rewardPerEpoch * 1 / 3);
        lvlStaking.claimRewards(2, bob);
        assertEq(LLP.balanceOf(bob), bobReward);
        bobReward += rewardPerEpoch / 2;
        lvlStaking.claimRewards(3, bob);
        assertEq(LLP.balanceOf(bob), bobReward);
        vm.stopPrank();
    }

    /* Full circle */
    function test_epoch_life_cycle() external {
        vm.startPrank(owner);
        uint256 start = block.timestamp + 1 days;
        LVL.mintTo(300 ether, bob);
        // lvlStaking.start(start);
        vm.stopPrank();

        vm.warp(1 days);
        uint256 currentEpoch = lvlStaking.currentEpoch();
        uint256 estTotalShare;
        uint256 aliceAmountAfterTax;

        // 1: Alice stake 100 ether when epoch start
        vm.startPrank(alice);
        LVL.approve(address(lvlStaking), 200 ether);
        {
            lvlStaking.stake(alice, 100 ether);
            aliceAmountAfterTax += (100 ether * 996) / 1000; // tax 4%
            // Verify LVL balance
            assertEq(LVL.balanceOf(alice), 100 ether);
            assertEq(LVL.balanceOf(address(lvlStaking)), aliceAmountAfterTax);
            // Verify alice state change
            (uint256 amount, uint256 claimedReward, uint256 accShare, uint256 lastUpdateAccShare) =
                lvlStaking.users(alice, currentEpoch);
            assertEq(lvlStaking.stakedAmounts(alice), aliceAmountAfterTax);
            assertEq(amount, aliceAmountAfterTax);
            assertEq(claimedReward, 0);
            assertEq(accShare, estTotalShare);
            assertEq(lastUpdateAccShare, start);
            // Verify epoch state change
            (uint256 startTime, uint256 endTime,, uint256 totalShare, uint256 lastUpdateShare,) =
                lvlStaking.epochs(currentEpoch);
            assertEq(startTime, start);
            assertEq(totalShare, estTotalShare);
            assertEq(lastUpdateShare, start);
            assertEq(lvlStaking.lastEpochTimestamp(), start);
        }
        // 2: Alice stake 100 ether after epoch start 1 hour
        {
            vm.warp(start + 1 hours);
            lvlStaking.stake(alice, 100 ether);
            aliceAmountAfterTax += (100 ether * 996) / 1000; // tax 4%
            estTotalShare += 1 hours * 99.6 ether;
            // Verify balance
            assertEq(LVL.balanceOf(alice), 0 ether);
            assertEq(LVL.balanceOf(address(lvlStaking)), aliceAmountAfterTax);
            // Verify user state change
            (uint256 amount, uint256 claimedReward, uint256 accShare, uint256 lastUpdateAccShare) =
                lvlStaking.users(alice, currentEpoch);
            assertEq(lvlStaking.stakedAmounts(alice), aliceAmountAfterTax);
            assertEq(amount, aliceAmountAfterTax);
            assertEq(claimedReward, 0);
            assertEq(accShare, estTotalShare);
            assertEq(lastUpdateAccShare, start + 1 hours);
            // verify epoch state change
            (uint256 startTime, uint256 endTime,, uint256 totalShare, uint256 lastUpdateShare,) =
                lvlStaking.epochs(currentEpoch);
            assertEq(startTime, start);
            assertEq(totalShare, estTotalShare);
            assertEq(lvlStaking.lastEpochTimestamp(), start);
            assertEq(lastUpdateShare, start + 1 hours);
        }
        vm.stopPrank();

        // 3 Bob stake 300 ether after epoch start 12 hours
        uint256 bobAmountAfterTax;
        vm.startPrank(bob);
        LVL.approve(address(lvlStaking), 300 ether);
        {
            vm.warp(start + 12 hours);
            lvlStaking.stake(bob, 200 ether);
            bobAmountAfterTax = (200 ether * 996) / 1000; // tax 4%
            estTotalShare += 11 hours * aliceAmountAfterTax;
            assertEq(LVL.balanceOf(bob), 100 ether);
            assertEq(LVL.balanceOf(address(lvlStaking)), bobAmountAfterTax * 2);
            // Verify user state change
            (uint256 amount, uint256 claimedReward, uint256 accShare, uint256 lastUpdateAccShare) =
                lvlStaking.users(bob, currentEpoch);
            assertEq(lvlStaking.stakedAmounts(bob), bobAmountAfterTax);
            assertEq(amount, bobAmountAfterTax);
            assertEq(claimedReward, 0);
            assertEq(accShare, 0);
            assertEq(lastUpdateAccShare, start + 12 hours);
            // Verify epoch state change
            (,,, uint256 totalShare, uint256 lastUpdateShare,) = lvlStaking.epochs(currentEpoch);
            assertEq(totalShare, estTotalShare);
            assertEq(lastUpdateShare, start + 12 hours);
        }

        // 4: Bob stake 100 ether after epoch start 20 hours
        {
            vm.warp(start + 20 hours);
            lvlStaking.stake(bob, 100 ether);
            estTotalShare += 8 hours * (aliceAmountAfterTax + bobAmountAfterTax);
            bobAmountAfterTax = (300 ether * 996) / 1000; // tax 4%
            assertEq(LVL.balanceOf(bob), 0 ether);
            assertEq(LVL.balanceOf(address(lvlStaking)), (500 ether * 996) / 1000);
            // Verify user state change
            (uint256 amount, uint256 claimedReward, uint256 accShare, uint256 lastUpdateAccShare) =
                lvlStaking.users(bob, currentEpoch);
            assertEq(lvlStaking.stakedAmounts(bob), bobAmountAfterTax);
            assertEq(amount, bobAmountAfterTax);
            assertEq(claimedReward, 0);
            assertEq(accShare, ((8 hours) * (200 ether * 996)) / 1000);
            assertEq(lastUpdateAccShare, start + 20 hours);

            // Verify epoch state change
            (,,, uint256 totalShare, uint256 lastUpdateShare,) = lvlStaking.epochs(currentEpoch);
            assertEq(totalShare, estTotalShare);
            assertEq(lastUpdateShare, start + 20 hours);
            vm.stopPrank();
        }
        // 5: Next epoch
        vm.warp(start + 1 days);
        {
            vm.startPrank(owner);
            lvlStaking.setEnableNextEpoch(true);
            lvlStaking.nextEpoch();
            estTotalShare += 4 hours * (aliceAmountAfterTax + bobAmountAfterTax);
            // Verify epoch state change
            assertEq(lvlStaking.currentEpoch(), currentEpoch + 1);
            assertEq(lvlStaking.lastEpochTimestamp(), start + 1 days);
            (uint256 startTime, uint256 endTime,, uint256 totalShare, uint256 lastUpdateShare,) =
                lvlStaking.epochs(currentEpoch);
            assertEq(endTime, start + 1 days);
            assertEq(lastUpdateShare, start + 1 days);
            assertEq(totalShare, estTotalShare);
        }
        // 6: Allocate reward
        {
            BTC.mintTo(100 ether, address(lvlStaking)); // mock withdraw fee
            lvlStaking.allocateReward(currentEpoch);
            uint256 alicePendingReward = lvlStaking.pendingRewards(currentEpoch, alice);
            uint256 bobPendingReward = lvlStaking.pendingRewards(currentEpoch, bob);
            assertApproxEqAbs(alicePendingReward + bobPendingReward, 100 ether, 1);
            vm.stopPrank();

            vm.startPrank(alice);
            lvlStaking.claimRewards(currentEpoch, alice);
            lvlStaking.claimRewards(currentEpoch, alice); // reward = 0
            assertEq(LLP.balanceOf(alice), alicePendingReward);
            vm.stopPrank();

            vm.startPrank(bob);
            lvlStaking.claimRewards(currentEpoch, bob);
            assertEq(LLP.balanceOf(bob), bobPendingReward);
            vm.stopPrank();
        }
    }

    /* ========== RESTRICTED ========== */
    /* Set Distributor */
    function test_set_distributor_revert_owner() external {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        lvlStaking.setDistributor(distributor);
    }

    function test_set_distributor_revert_invalid_address() external {
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        lvlStaking.setDistributor(address(0));
    }

    function test_set_distributor_success() external {
        vm.prank(owner);
        lvlStaking.setDistributor(distributor);
    }

    /* Set Epoch Duration */
    function test_set_epoch_duration_revert_owner() external {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        lvlStaking.setEpochDuration(1 days);
    }

    function test_set_epoch_duration_revert_invalid_variable() external {
        vm.prank(owner);
        vm.expectRevert("< MIN_EPOCH_DURATION");
        lvlStaking.setEpochDuration(1 hours);
    }

    function test_set_epoch_duration_success() external {
        vm.prank(owner);
        lvlStaking.setEpochDuration(1 days);
    }

    /* Set Enable Next Batch */
    function test_set_enable_next_batch_revert_permission() external {
        vm.prank(alice);
        vm.expectRevert("Caller is not the distributor or owner");
        lvlStaking.setEnableNextEpoch(true);
    }

    function test_set_enable_next_batch_success() external {
        vm.prank(owner);
        lvlStaking.setEnableNextEpoch(true);
    }

    function test_swap_revert_permission() external {
        vm.prank(owner);
        BTC.mintTo(100 ether, address(lvlStaking));
        vm.prank(alice);
        vm.expectRevert("Caller is not the distributor or owner");
        lvlStaking.swap(address(BTC), address(USDT), 100 ether, 0);
    }

    function test_withdraw_revert_permission() external {
        vm.prank(owner);
        BTC.mintTo(100 ether, address(lvlStaking));
        vm.prank(alice);
        vm.expectRevert("Caller is not the distributor or owner");
        lvlStaking.withdrawToken(address(BTC), alice, 100 ether);
    }

    function test_withdraw_revert_to_address() external {
        vm.startPrank(owner);
        BTC.mintTo(100 ether, address(lvlStaking));
        vm.expectRevert("Invalid address");
        lvlStaking.withdrawToken(address(BTC), address(0), 100 ether);
    }

    function test_withdraw_success() external {
        vm.startPrank(owner);
        BTC.mintTo(100 ether, address(lvlStaking));
        lvlStaking.withdrawToken(address(BTC), alice, 100 ether);
        assertEq(BTC.balanceOf(address(lvlStaking)), 0 ether);
        assertEq(BTC.balanceOf(address(alice)), 100 ether);
    }

    /* Set Fee Tokens */
    function test_set_fee_token_revert_invalid_address() external {
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        lvlStaking.setFeeToken(address(0), true);
    }

    function test_set_fee_token_success() external {
        vm.prank(owner);
        lvlStaking.setFeeToken(address(BTC), true);
        assertEq(lvlStaking.feeTokens(address(BTC)), true);
    }

    /* Set Convert LLP Tokens */
    function test_set_convert_token_revert_owner() external {
        vm.prank(alice);
        address[] memory _tokens = new address[](3);
        _tokens[0] = address(weth);
        _tokens[1] = address(BTC);
        _tokens[2] = address(USDT);
        vm.expectRevert("Ownable: caller is not the owner");
        lvlStaking.setConvertLLPTokens(_tokens);
    }

    function test_set_convert_token_revert_invalid_address() external {
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        address[] memory _tokens = new address[](3);
        _tokens[0] = address(weth);
        _tokens[1] = address(BTC);
        lvlStaking.setConvertLLPTokens(_tokens);
    }

    function test_set_convert_token_success() external {
        vm.prank(owner);
        address[] memory _tokens = new address[](3);
        _tokens[0] = address(weth);
        _tokens[1] = address(BTC);
        _tokens[2] = address(USDT);
        lvlStaking.setConvertLLPTokens(_tokens);
    }

    // =============== EVENTS ===============
    event Staked(address indexed _from, address indexed _to, uint256 _time, uint256 _stakedAmount, uint256 _taxAmount);
    event Unstaked(address indexed _from, address indexed _to, uint256 _time, uint256 _amount);
}
