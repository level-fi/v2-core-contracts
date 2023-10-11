pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/staking/lvl/LevelOmniStakingReserve.sol";
import {WETH9} from "./mocks/WETH.sol";
import {ETHUnwrapper} from "./mocks/ETHUnwrapper.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {ILPToken} from "../src/interfaces/ILPToken.sol";

contract LevelOmniStakingReserveTest is Test {
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

    LevelOmniStakingReserve lvlStakingReserve;

    address[] convertLLPTokens = new address[](2);

    function setUp() external {
        vm.warp(0);
        vm.startPrank(owner);
        BTC = new MockERC20("BTC", "BTC", 18);
        USDT = new MockERC20("USDT", "USDT", 18);
        weth = new WETH9();

        ethUnwrapper = new ETHUnwrapper(address(weth));
        pool = new MockPool();
        LLP = pool.lpToken();

        Proxy omniStakingProxy = new Proxy(
            address(new LevelOmniStakingReserve()),
            address(proxyAdmin),
            new bytes(0)
        );
        lvlStakingReserve = LevelOmniStakingReserve(address(omniStakingProxy));
        lvlStakingReserve.initialize(address(pool), address(LLP), address(weth), address(ethUnwrapper));

        convertLLPTokens[0] = address(weth);
        convertLLPTokens[1] = address(BTC);
        lvlStakingReserve.setConvertLLPTokens(convertLLPTokens);

        lvlStakingReserve.setFeeToken(address(BTC), true);
        lvlStakingReserve.setDistributor(distributor);
        vm.stopPrank();
    }

    function test_convert_to_llp_revert_invalid_address() external {
        vm.prank(owner);
        BTC.mintTo(100 ether, address(lvlStakingReserve));
        vm.prank(distributor);
        vm.expectRevert(abi.encodeWithSelector(LevelOmniStakingReserve.ZeroAddress.selector));
        lvlStakingReserve.convertTokenToLLP(address(0));
    }

    function test_convert_to_llp_revert_invalid_role() external {
        vm.prank(owner);
        BTC.mintTo(100 ether, address(lvlStakingReserve));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LevelOmniStakingReserve.Unauthorized.selector));
        lvlStakingReserve.convertTokenToLLP(alice);
    }

    function test_convert_to_llp_success() external {
        vm.prank(owner);
        BTC.mintTo(100 ether, address(lvlStakingReserve));
        vm.prank(distributor);
        lvlStakingReserve.convertTokenToLLP(distributor);
        assertEq(LLP.balanceOf(distributor), 100 ether);
    }

    function test_convert_to_llp_2_revert() external {
        vm.prank(distributor);
        address[] memory tokens = new address[](1);
        tokens[0] = address(BTC);
        uint256[] memory amounts = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(LevelOmniStakingReserve.LengthMissMatch.selector));
        lvlStakingReserve.convertTokenToLLP(tokens, amounts, distributor);
    }

    function test_convert_to_llp_2_success() external {
        vm.prank(owner);
        BTC.mintTo(100 ether, address(lvlStakingReserve));
        vm.prank(distributor);
        address[] memory tokens = new address[](1);
        tokens[0] = address(BTC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;
        lvlStakingReserve.convertTokenToLLP(tokens, amounts, distributor);
        assertEq(LLP.balanceOf(distributor), 100 ether);
    }
}
