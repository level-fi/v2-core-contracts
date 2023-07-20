// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {LvlBatchAuctionFactory} from "src/auction/LvlBatchAuctionFactory.sol";
import {LvlBatchAuction} from "src/auction/LvlBatchAuction.sol";
import {AuctionTreasury} from "src/treasury/AuctionTreasury.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "./Constants.s.sol";

contract AuctionTreasuryTest is Test {
    address owner = address(bytes20("owner"));
    address user1 = address(bytes20("user1"));
    address payable user2 = payable(address(bytes20("user2")));
    address user3 = address(bytes20("user3"));
    address admin = address(bytes20("admin"));
    address cashTreasury = address(bytes20("cashTreasury"));
    address llpReserve = address(bytes20("llpReserve"));
    address proxyAdmin = address(bytes20("proxyAdmin"));

    function setUp() external {
        MockERC20 erc20 = new MockERC20("LVL Token", "LVL", 18);
        vm.etch(Constants.LVL, address(erc20).code);
        vm.etch(Constants.USDT, address(erc20).code);
    }

    function createTreasury() internal returns (AuctionTreasury treasury) {
        vm.startPrank(owner);
        AuctionTreasury treasuryImpl = new AuctionTreasury();
        Proxy proxy = new Proxy(address(treasuryImpl), proxyAdmin, new bytes(0));
        treasury = AuctionTreasury(address(proxy));

        // should validate init params
        vm.expectRevert("Invalid address");
        treasury.initialize(address(0), llpReserve);

        vm.expectRevert("Invalid address");
        treasury.initialize(cashTreasury, address(0));

        treasury.initialize(cashTreasury, llpReserve);
        vm.stopPrank();
    }

    function test_init_aution_treasury() external {
        AuctionTreasury treasury = createTreasury();
        assertEq(treasury.cashTreasury(), cashTreasury);
        assertEq(treasury.llpReserve(), llpReserve);
        assertEq(treasury.owner(), owner);
    }

    function test_set_admin() external {
        AuctionTreasury treasury = createTreasury();
        address eve = address(bytes20("eve"));
        vm.prank(eve);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        treasury.setAdmin(eve);

        vm.prank(owner);
        vm.expectRevert("Invalid address");
        treasury.setAdmin(address(0));

        vm.prank(owner);
        treasury.setAdmin(admin);
        assertEq(treasury.admin(), admin);
    }

    function test_set_lvl_auction_factory() external {
        AuctionTreasury treasury = createTreasury();
        address eve = address(bytes20("eve"));
        address lvlAuctionFactory = address(bytes20("lvl-auction-factory"));
        vm.prank(eve);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        treasury.setLVLAuctionFactory(lvlAuctionFactory);

        vm.prank(owner);
        vm.expectRevert("Invalid address");
        treasury.setLVLAuctionFactory(address(0));

        vm.prank(owner);
        treasury.setLVLAuctionFactory(lvlAuctionFactory);
        assertEq(treasury.LVLAuctionFactory(), lvlAuctionFactory);

        deal(Constants.LVL, address(treasury), 1000 ether);
        vm.prank(eve);
        vm.expectRevert(bytes("only LVLAuctionFactory"));
        treasury.transferLVL(eve, 10 ether);

        vm.prank(lvlAuctionFactory);
        vm.expectEmit();
        emit Transfer(address(treasury), address(lvlAuctionFactory), 10 ether);
        treasury.transferLVL(lvlAuctionFactory, 10 ether);
    }

    function test_distribute_usdt() external {
        // arrange
        AuctionTreasury treasury = createTreasury();
        address eve = address(bytes20("eve"));

        vm.prank(owner);
        treasury.setAdmin(admin);
        assertEq(treasury.admin(), admin);

        deal(Constants.USDT, address(treasury), 1000 ether);
        // act
        vm.prank(eve);
        vm.expectRevert(bytes("Only Owner or Admin can operate"));
        treasury.distribute();

        vm.prank(admin);
        vm.expectEmit();
        emit Transfer(address(treasury), address(cashTreasury), 750 ether);
        vm.expectEmit();
        emit Transfer(address(treasury), address(llpReserve), 250 ether);
        treasury.distribute();
    }

    function test_distribute_should_revert_when_not_inited() external {
        // arrange
        AuctionTreasury treasuryImpl = new AuctionTreasury();
        Proxy proxy = new Proxy(address(treasuryImpl), proxyAdmin, new bytes(0));

        vm.expectRevert();
        AuctionTreasury(address(proxy)).distribute();
    }

    function test_distribute_usdt_not_revert_when_fund_empty() external {
        // arrange
        AuctionTreasury treasury = createTreasury();

        vm.prank(owner);
        treasury.setAdmin(admin);
        assertEq(treasury.admin(), admin);

        vm.prank(admin);
        treasury.distribute();
    }

    function test_recover_fund() external {
        AuctionTreasury treasury = createTreasury();
        address eve = address(bytes20("eve"));
        vm.prank(eve);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        treasury.recoverFund(Constants.LVL, eve, 1 ether);

        deal(Constants.LVL, address(treasury), 1 ether);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, Constants.LVL);
        emit Transfer(address(treasury), address(owner), 1 ether);
        treasury.recoverFund(Constants.LVL, owner, 1 ether);
    }

    function test_transfer_ownership() external {
        AuctionTreasury treasury = createTreasury();
        address eve = address(bytes20("eve"));

        vm.prank(eve);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        treasury.transferOwnership(eve);

        address newOwner = address(bytes20("owner"));
        vm.prank(owner);
        vm.expectEmit();
        emit OwnershipTransferred(owner, newOwner);
        treasury.transferOwnership(newOwner);

        assertEq(treasury.owner(), newOwner);
    }

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}
