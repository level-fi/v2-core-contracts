pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/staking/lvl/ClaimHelper.sol";
import {WETH9} from "./mocks/WETH.sol";
import {ETHUnwrapper} from "./mocks/ETHUnwrapper.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {ILPToken} from "../src/interfaces/ILPToken.sol";

contract MockOmniStaking {
    using SafeERC20 for IERC20;

    IERC20 public LLP;

    constructor(address _llp) {
        LLP = IERC20(_llp);
    }

    function claimRewardsOnBehalf(address _user, uint256 _epoch, address _to) external {
        LLP.safeTransfer(_to, 100 ether);
    }
}

contract LevelClaimHelperTest is Test {
    address owner = address(bytes20("owner"));
    address distributor = address(bytes20("distributor"));
    address alice = address(bytes20("alice"));
    address proxyAdmin = address(bytes20("proxyAdmin"));

    ILPToken LLP;
    MockERC20 BTC;
    MockERC20 USDT;
    WETH9 weth;

    ETHUnwrapper ethUnwrapper;
    MockPool pool;
    MockOmniStaking lvlStaking;
    MockOmniStaking lvlUsdtStaking;

    ClaimHelper claimHelper;

    function setUp() external {
        vm.warp(0);
        vm.startPrank(owner);

        BTC = new MockERC20("BTC", "BTC", 18);
        USDT = new MockERC20("USDT", "USDT", 18);
        weth = new WETH9();

        ethUnwrapper = new ETHUnwrapper(address(weth));
        pool = new MockPool();
        LLP = pool.lpToken();

        lvlStaking = new MockOmniStaking(address(LLP));
        lvlUsdtStaking = new MockOmniStaking(address(LLP));

        claimHelper =
        new ClaimHelper(address(pool), address(LLP), address(weth), address(ethUnwrapper), address(lvlStaking), address(lvlUsdtStaking));

        BTC.mint(2000 ether);
        USDT.mint(2000 ether);
        BTC.approve(address(pool), 2000 ether);
        USDT.approve(address(pool), 2000 ether);

        pool.addLiquidity(address(0), address(BTC), 1000 ether, 0, address(lvlStaking));
        pool.addLiquidity(address(0), address(USDT), 1000 ether, 0, address(lvlStaking));
        pool.addLiquidity(address(0), address(BTC), 1000 ether, 0, address(lvlUsdtStaking));
        pool.addLiquidity(address(0), address(USDT), 1000 ether, 0, address(lvlUsdtStaking));

        vm.stopPrank();
    }

    function test_claim_reward() external {
        uint256[] memory _epochs = new uint256[](1);
        _epochs[0] = 0;

        vm.prank(owner);
        claimHelper.claimRewards(_epochs, owner);
        assertEq(LLP.balanceOf(owner), 200 ether);
    }

    function test_claim_reward_to_token() external {
        uint256[] memory _epochs = new uint256[](1);
        _epochs[0] = 0;

        vm.prank(owner);
        claimHelper.claimRewardsToSingleToken(_epochs, owner, address(BTC), 200 ether);
        assertEq(BTC.balanceOf(owner), 200 ether);
    }

    function test_claim_reward_multiple() external {
        uint256[] memory _epochs = new uint256[](3);
        _epochs[0] = 0;
        _epochs[1] = 1;
        _epochs[2] = 2;

        vm.prank(owner);
        claimHelper.claimRewards(_epochs, owner);
        assertEq(LLP.balanceOf(owner), 600 ether);
    }

    function test_claim_reward_to_token_multiple() external {
        uint256[] memory _epochs = new uint256[](3);
        _epochs[0] = 0;
        _epochs[1] = 1;
        _epochs[2] = 2;

        vm.prank(owner);
        claimHelper.claimRewardsToSingleToken(_epochs, owner, address(BTC), 600 ether);
        assertEq(BTC.balanceOf(owner), 600 ether);
    }

    function test_claim_reward_revert_slippage() external {
        uint256[] memory _epochs = new uint256[](3);
        _epochs[0] = 0;
        _epochs[1] = 1;
        _epochs[2] = 2;

        vm.prank(owner);
        vm.expectRevert();
        claimHelper.claimRewardsToSingleToken(_epochs, owner, address(BTC), 1000 ether);
    }

    function test_claim_reward_revert_invalid_token() external {
        uint256[] memory _epochs = new uint256[](3);
        _epochs[0] = 0;
        _epochs[1] = 1;
        _epochs[2] = 2;

        vm.prank(owner);
        vm.expectRevert();
        claimHelper.claimRewardsToSingleToken(_epochs, owner, address(0), 600 ether);
    }
}
