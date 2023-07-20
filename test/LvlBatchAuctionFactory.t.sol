// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {LvlBatchAuctionFactory} from "src/auction/LvlBatchAuctionFactory.sol";
import {LvlBatchAuction} from "src/auction/LvlBatchAuction.sol";
import {AuctionTreasury} from "src/treasury/AuctionTreasury.sol";
import "./Constants.s.sol";

interface IERC20Metadata {
    function decimals() external returns (uint8);
}
/**
 * @notice Test batch auction factory
 */

contract LvlBatchAuctionFactoryTest is Test {
    address owner = address(bytes20("owner"));
    address user1 = address(bytes20("user1"));
    address payable user2 = payable(address(bytes20("user2")));
    address user3 = address(bytes20("user3"));
    address admin = address(bytes20("admin"));
    address eve = address(bytes20("eve"));

    function setUp() external {
        MockERC20 erc20 = new MockERC20("anyToken", "any", 18);
        vm.etch(Constants.LVL, address(erc20).code);
        vm.etch(Constants.USDT, address(erc20).code);
        // store decimals
        vm.store(Constants.LVL, bytes32(abi.encode(5)), bytes32(abi.encode(uint8(18))));
        vm.store(Constants.USDT, bytes32(abi.encode(5)), bytes32(abi.encode(uint8(6))));
    }

    function test_set_auction_admin() external {
        address treasury = address(bytes20("treasury"));
        vm.prank(owner);
        LvlBatchAuctionFactory auctionFactory = new LvlBatchAuctionFactory(
            treasury,
            admin,
            1 days,
            2e18
        );

        assertEq(auctionFactory.owner(), owner);

        vm.prank(owner);
        vm.expectRevert(bytes("Invalid address"));
        auctionFactory.setAdmin(address(0));

        vm.prank(eve);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        auctionFactory.setAdmin(eve);

        vm.prank(owner);
        auctionFactory.setAdmin(admin);
        assertEq(auctionFactory.admin(), admin);
    }

    function test_set_auction_treasury() external {
        address treasury = address(bytes20("treasury"));
        vm.prank(owner);
        LvlBatchAuctionFactory auctionFactory = new LvlBatchAuctionFactory(
            treasury,
            admin,
            1 days,
            2e18
        );

        vm.startPrank(owner);
        vm.expectRevert();
        auctionFactory.setTreasury(address(0));

        auctionFactory.setTreasury(treasury);
        vm.stopPrank();
    }

    function test_set_auction_vesting_duration_factory() external {
        address treasury = address(bytes20("treasury"));
        vm.prank(owner);
        LvlBatchAuctionFactory auctionFactory = new LvlBatchAuctionFactory(
            treasury,
            admin,
            1 days,
            2e18
        );

        vm.startPrank(owner);
        auctionFactory.setVestingDuration(1 days);
        vm.stopPrank();
    }

    function createFactory() internal returns (address treasury, LvlBatchAuctionFactory factory) {
        address cashTreasury = address(bytes20("cashTreasury"));
        address llpReserve = address(bytes20("llpReserve"));
        address proxyAdmin = address(bytes20("proxyAdmin"));
        vm.startPrank(owner);
        AuctionTreasury treasuryImpl = new AuctionTreasury();
        bytes memory initData = abi.encodeWithSelector(AuctionTreasury.initialize.selector, cashTreasury, llpReserve);
        Proxy proxy = new Proxy(address(treasuryImpl), proxyAdmin, initData);
        treasury = address(proxy);

        uint64 vestingDuration = 1 days;
        uint64 minCeilingPrice = 2e18;
        factory = new LvlBatchAuctionFactory(
            treasury,
            admin,
            vestingDuration,
            minCeilingPrice
        );
        console.log(AuctionTreasury(treasury).owner(), owner);
        assertEq(AuctionTreasury(treasury).owner(), owner);
        AuctionTreasury(treasury).setLVLAuctionFactory(address(factory));
        deal(Constants.LVL, treasury, 1_000_000 ether);
        vm.stopPrank();
    }

    function test_create_auction_not_allow_unauthorized() external {
        (, LvlBatchAuctionFactory factory) = createFactory();
        vm.prank(eve);
        vm.expectRevert("Ownable: caller is not the owner");
        uint256 start = block.timestamp + 1;
        uint256 end = start + 1 days;
        factory.createAuction(10 ether, uint64(start), uint64(end), 10 ether, 0);
    }

    function test_create_auction_validate_time() external {
        (, LvlBatchAuctionFactory factory) = createFactory();

        {
            vm.prank(owner);
            vm.expectRevert("< MIN_AUCTION_DURATION");
            uint256 start = block.timestamp + 1;
            uint256 end = block.timestamp + 1;
            factory.createAuction(10 ether, uint64(start), uint64(end), 10 ether, 0);
        }

        {
            vm.prank(owner);
            vm.expectRevert("ceilingPrice < minimum ceiling price");
            uint256 start = block.timestamp + 1;
            uint256 end = start + 1 days;
            factory.createAuction(10 ether, uint64(start), uint64(end), 1 ether, 0);
        }

        {
            vm.prank(owner);
            vm.expectRevert("> MAX_AUCTION_DURATION");
            uint256 start = block.timestamp + 1;
            uint256 end = start + 15 days;
            factory.createAuction(10 ether, uint64(start), uint64(end), 10 ether, 0);
        }
    }

    function test_create_auction_success() external {
        (, LvlBatchAuctionFactory factory) = createFactory();
        vm.prank(owner);
        factory.createAuction(
            10 ether, uint64(block.timestamp + 1000), uint64(block.timestamp + 1000 + 1 days), 10e18, 0
        );
        assertEq(factory.totalAuctions(), 1);
    }
}
