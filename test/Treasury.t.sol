pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "../src/treasury/Treasury.sol";
import "./mocks/MockPool.sol";
import "./mocks/MockLpToken.sol";
import {WETH9} from "./mocks/WETH.sol";
import {ETHUnwrapper} from "./mocks/ETHUnwrapper.sol";

contract TreasuryTest is Test {
    address admin = 0x9Cb2f2c0122a1A8C90f667D1a55E5B45AC8b6086;
    address controller = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;
    address redemption = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
    address spender = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;

    Treasury treasury;
    MockPool pool;

    WETH9 public WETH;
    ETHUnwrapper ethUnwrapper;

    MockERC20 USDT;
    MockERC20 BTC;
    LPToken LLP;

    function setUp() external {
        vm.startPrank(admin);

        USDT = new MockERC20("USDT", "USDT", 18);
        BTC = new MockERC20("BTC", "BTC", 18);
        USDT.mintTo(1 ether, admin);
        BTC.mintTo(1 ether, admin);

        // WETH = new WETH9();
        // ethUnwrapper = new ETHUnwrapper(address(WETH));

        address proxyAdmin = address(bytes20("proxyAdmin"));
        Proxy proxy = new Proxy(
            address(new Treasury()),
            proxyAdmin,
            abi.encodeWithSelector(Treasury.initialize.selector)
        );
        treasury = Treasury(address(proxy));

        address weth = address(treasury.weth());
        vm.etch(weth, address(new WETH9()).code);
        vm.etch(address(treasury.ethUnwrapper()), address(new ETHUnwrapper(weth)).code);
        WETH = WETH9(payable(weth));

        address llp = treasury.LLP();
        LLP = LPToken(llp);
        vm.etch(llp, address(new LPToken("a", "b" )).code);

        address poolAddress = address(treasury.pool());
        vm.etch(poolAddress, address(new MockPool()).code);
        pool = MockPool(poolAddress);
        pool.setLpToken(llp);

        vm.deal(admin, 2 ether);
        WETH.deposit{value: 2 ether}();
        WETH.transfer(address(treasury), 1 ether);
        WETH.transfer(address(pool), 1 ether);
        BTC.mintTo(1 ether, address(treasury));
        USDT.mintTo(1 ether, address(treasury));

        BTC.approve(address(pool), 1 ether);
        pool.addLiquidity(address(0), address(BTC), 1 ether, 0, address(treasury));

        bytes32 adminRole = treasury.DEFAULT_ADMIN_ROLE();
        treasury.grantRole(adminRole, controller);

        bytes32 controllerRole = treasury.CONTROLLER_ROLE();
        treasury.grantRole(controllerRole, controller);
        vm.stopPrank();
    }

    function test_control_controller() external {
        bytes32 controllerRole = treasury.CONTROLLER_ROLE();

        // revert grant controller !admin
        vm.startPrank(spender);
        vm.expectRevert();
        treasury.grantRole(controllerRole, controller);
        vm.stopPrank();

        // success grant controller
        vm.startPrank(admin);
        treasury.grantRole(controllerRole, controller);
        assertEq(treasury.hasRole(controllerRole, controller), true);

        // success revoke controller
        treasury.revokeRole(controllerRole, controller);
        assertFalse(treasury.hasRole(controllerRole, controller));
        vm.stopPrank();
    }

    function test_convert_to_llp() external {
        vm.startPrank(controller);
        treasury.convertToLLP(address(BTC), 1 ether, 1 ether);
        vm.stopPrank();
    }
}
