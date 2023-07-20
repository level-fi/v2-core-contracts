pragma solidity 0.8.18;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "src/referral/ReferralRewarder.sol";
import "./mocks/MockERC20.sol";

struct NodeData {
    uint256 id;
    address user;
    uint256 amount;
    uint256 chainId;
    bytes32[] proof;
}

struct Json {
    bytes32 root;
    NodeData[] data;
}

// Test data located at /test/data/merkle-tree.json
contract TestReferralRewarder is Test {
    address owner;
    address alice = address(bytes20("alice"));
    address controller = address(bytes20("controller"));
    ReferralRewarder rewarder;
    bytes32[] public merkleProof;
    bytes32 constant ROOT = 0xa79940ba078db02617a683223d35067bdae023c3ccb35e5476440d27c3ce19a2;
    uint256 constant TOTAL_REWARDS = 7572592785077290858000;
    address USER = 0x6B74A5A0FD40fE3a88996166D157586B5be1e795;
    uint USER_REWARDS = 114000000000000000000;

    function setUp() external {
        owner = msg.sender;
    }

    function test_init() external {
        vm.startPrank(owner);
        init();
        assertTrue(address(rewarder) != address(0));
        vm.stopPrank();
    }

    function test_create_airdrop() external {
        vm.startPrank(owner);
        init();
        rewarder.addEpoch(24, ROOT, bytes32("ipfs-decoded"), TOTAL_REWARDS);
        (bytes32 _merkleRoot,,,,,) = rewarder.epoches(24);
        assertTrue(_merkleRoot != bytes32(0));

        vm.expectRevert("epoch exists");
        rewarder.addEpoch(24, ROOT, bytes32("ipfs-decoded"), TOTAL_REWARDS);
        vm.stopPrank();
        vm.startPrank(alice);

        vm.expectRevert("unauthorized");
        rewarder.addEpoch(25, ROOT, bytes32("ipfs-decoded"), TOTAL_REWARDS);
        vm.stopPrank();
    }

    function test_get_claimable() external {
        vm.startPrank(owner);
        init();
        rewarder.addEpoch(24, ROOT, bytes32("ipfs-decoded"), TOTAL_REWARDS);

        uint256 _claimableRewards = rewarder.claimableRewards(24, 3, USER, USER_REWARDS, merkleProof);

        assertEq(0, _claimableRewards);
        vm.warp(block.timestamp + 7 days);
        _claimableRewards = rewarder.claimableRewards(24, 3, USER, USER_REWARDS, merkleProof);
        console.log("_claimableRewards", _claimableRewards);
        assertEq(USER_REWARDS, _claimableRewards);
        vm.stopPrank();
    }

    function test_claim_rewards() external {
        vm.startPrank(owner);
        init();
        rewarder.addEpoch(24, ROOT, bytes32("ipfs-decoded"), TOTAL_REWARDS);

        vm.stopPrank();

        uint256 _startTime = block.timestamp;

        vm.warp(block.timestamp + (block.timestamp + 7 days) / 2);

        vm.startPrank(USER);
        rewarder.claimRewards(24, USER, 3, USER_REWARDS, merkleProof);

        uint256 _claimableRewards = rewarder.claimableRewards(24, 3, USER, USER_REWARDS, merkleProof);

        assertEq(_claimableRewards, 0);
        uint256 _claimed = rewarder.rewardReceived(24, USER);
        assertEq(_claimed, USER_REWARDS / 2);

        vm.warp(_startTime + 7 days);
        _claimableRewards = rewarder.claimableRewards(24, 3, USER, USER_REWARDS, merkleProof);
        assertEq(_claimableRewards, USER_REWARDS - _claimed);
        assertEq(MockERC20(rewarder.LVL()).balanceOf(USER), _claimableRewards);
        rewarder.claimRewards(24, USER, 3, USER_REWARDS, merkleProof);
        assertEq(MockERC20(rewarder.LVL()).balanceOf(USER), USER_REWARDS);
        vm.stopPrank();
    }

    function test_set_controller() external {
        vm.startPrank(owner);
        init();
        vm.expectRevert("invalid address");
        rewarder.setController(address(0));

        rewarder.setController(controller);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        rewarder.setController(controller);
        vm.stopPrank();
    }

    function test_recover_fund() external {
        vm.startPrank(owner);
        init();
        uint256 _amount = MockERC20(rewarder.LVL()).balanceOf(address(rewarder));
        vm.expectRevert("invalid address");
        rewarder.recoverFund(address(0), _amount);
        rewarder.recoverFund(alice, _amount);
        assertEq(_amount, 1_000_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        rewarder.recoverFund(alice, _amount);
        vm.stopPrank();
    }

    function init() internal {
        MockERC20 lvl = new MockERC20("LVL", "LVL", 18);
        address proxyAdmin = address(new ProxyAdmin());
        ReferralRewarder _rewarder = new ReferralRewarder();
        Proxy proxy =
        new Proxy(address(_rewarder), proxyAdmin, abi.encodeWithSelector(ReferralRewarder.initialize.selector, controller));
        rewarder = ReferralRewarder(address(proxy));
        vm.etch(rewarder.LVL(), address(lvl).code);
        MockERC20(rewarder.LVL()).mintTo(1_000_000e18, address(rewarder));

        merkleProof.push(0x92cb3c0fb201be40f69394d63ef7f8ed692ee2849e9fe82a331d502ea5c80d14);
        merkleProof.push(0x15e2fe328b4c1b6901c63288e88914c7af34d09e0843ca26ffbfe1e3d31c27f7);
    }
}
