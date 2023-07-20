// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {LvlBatchAuction} from "src/auction/LvlBatchAuction.sol";

contract BatchAuctionTest is Test {
    address owner = address(bytes20("owner"));
    address treasury = address(bytes20("treasury"));
    address admin = address(bytes20("admin"));
    address eve = address(bytes20("eve"));
    address alice = address(bytes20("alice"));
    address bob = address(bytes20("bob"));
    address LVL;
    address USDT;

    function setUp() external {
        LVL = address(new MockERC20("LVL", "", 18));
        USDT = address(new MockERC20("USDT", "", 6));
        deal(USDT, alice, 20_000e6);
        deal(USDT, bob, 20_000e6);
    }

    /**
     * require(_endTime < 10000000000, "unix timestamp in seconds");
     * require(_startTime >= block.timestamp, "start time < current time");
     * require(_endTime > _startTime, "end time < start price");
     * require(_totalTokens != 0, "total tokens = 0");
     * require(_ceilingPrice > _minPrice, "ceiling price < minimum price");
     * require(_ceilingPrice >= _minimumCeilingPrice, "ceiling price < minimum ceiling price");
     * require(_treasury != address(0), "address = 0");
     * require(_admin != address(0), "address = 0");
     * require(IERC20Metadata(_auctionToken).decimals() == 18, "decimals != 18");
     */
    function test_create_auction_should_validate_params() external {
        uint64 invalid_valid_unix_timestamp = 10000000000;
        vm.warp(1000); // a random valid time
        uint64 tokenAmount = 1 ether;
        check_validate_init_params(
            LVL,
            USDT,
            tokenAmount,
            1,
            invalid_valid_unix_timestamp,
            1,
            1,
            0,
            admin,
            treasury,
            1000,
            "unix timestamp in seconds"
        );

        check_validate_init_params(
            LVL, USDT, tokenAmount, 1, 10002, 1, 1, 0, admin, treasury, 1 minutes, "start time < current time"
        );

        check_validate_init_params(
            LVL, USDT, tokenAmount, 10000, 9999, 1, 1, 0, admin, treasury, 1 minutes, "end time < start price"
        );

        check_validate_init_params(LVL, USDT, 0, 10000, 20000, 1, 1, 0, admin, treasury, 1 minutes, "total tokens = 0");

        check_validate_init_params(
            LVL,
            USDT,
            tokenAmount,
            10000,
            20000,
            100, /* min ceiling price*/
            99, /* celing price */
            0,
            admin,
            treasury,
            1 minutes,
            "ceiling price < minimum ceiling price"
        );

        check_validate_init_params(
            LVL,
            USDT,
            tokenAmount,
            10000,
            20000,
            100, /* min ceiling price*/
            100, /* celing price */
            101, /* min price */
            admin,
            treasury,
            1 minutes,
            "ceiling price < minimum price"
        );
        check_validate_init_params(
            LVL,
            USDT,
            tokenAmount,
            10000,
            20000,
            100, /* min ceiling price*/
            100, /* celing price */
            0, /* min price */
            address(0),
            treasury,
            1 minutes,
            "address = 0"
        );
        check_validate_init_params(
            LVL,
            USDT,
            tokenAmount,
            10000,
            20000,
            100, /* min ceiling price*/
            100, /* celing price */
            0, /* min price */
            admin,
            address(0),
            1 minutes,
            "address = 0"
        );
    }

    function check_validate_init_params(
        address _auctionToken,
        address _payToken,
        uint128 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint128 _minimumCeilingPrice,
        uint128 _ceilingPrice,
        uint128 _minimumPrice,
        address _admin,
        address _treasury,
        uint64 _vestingDuration,
        string memory message
    ) internal {
        vm.expectRevert(bytes(message));
        new LvlBatchAuction(
            _auctionToken,
            _payToken,
            _totalTokens,
            _startTime,
            _endTime,
            _minimumCeilingPrice,
            _ceilingPrice,
            _minimumPrice,
            _admin,
            _treasury,
            _vestingDuration
        );
    }

    function test_create_auction_success() external {
        vm.startPrank(owner);

        vm.warp(1000);
        LvlBatchAuction auction = new LvlBatchAuction(
            LVL,
            USDT,
            10 ether,
            1000,
            2000,
            1 ether,
            2 ether,
            1,
            admin,
            treasury,
            1 days
        );
        assertEq(auction.auctionTokenDecimals(), 18);
        assertEq(auction.startTime(), 1000);
        assertEq(auction.endTime(), 2000);
        assertEq(auction.admin(), admin);
        assertEq(auction.auctionTreasury(), treasury);
        assertEq(auction.minimumCeilingPrice(), 1 ether);
        assertEq(auction.ceilingPrice(), 2 ether);
        assertEq(auction.minPrice(), 1);
        assertEq(auction.vestingDuration(), 1 days);
    }

    function initAuction() internal returns (LvlBatchAuction auction) {
        auction = new LvlBatchAuction(
            LVL,
            USDT,
            10_000 ether,
            1100, // start
            2000, // end
            100, // min ceiling price
            2e6, // ceiling price
            1e6, // min price
            admin,
            treasury,
            1000
        );
        deal(LVL, address(auction), 10_000 ether);
    }

    function test_commit_fail_when_auction_not_live() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        deal(USDT, alice, 10_000e6);
        vm.prank(alice);
        IERC20(USDT).approve(address(auction), 5_000e6);

        vm.warp(1001);
        assertFalse(auction.isOpen());

        vm.prank(alice);
        vm.expectRevert(bytes("aution not live"));
        auction.commitTokens(alice, 5_000e6);

        vm.warp(2001);
        assertFalse(auction.isOpen());
        vm.prank(alice);
        vm.expectRevert(bytes("aution not live"));
        auction.commitTokens(alice, 5_000e6);
    }

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_commit_success() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(alice);
        IERC20(USDT).approve(address(auction), type(uint256).max);

        vm.prank(bob);
        IERC20(USDT).approve(address(auction), type(uint256).max);

        uint256 startTime = auction.startTime();
        vm.warp(startTime);
        assertTrue(auction.isOpen());

        vm.prank(alice);
        vm.expectEmit(true, true, true, true, USDT);
        emit Transfer(alice, address(auction), 5_000e6);
        auction.commitTokens(alice, 5_000e6);
        assertEq(auction.commitmentsTotal(), 5_000e6);
        assertEq(auction.commitments(alice), 5_000e6);

        /*
            seld = 10k LVL
            total bid = 5k USDT
            price = 0.5 USDT / LVL = 5e17
        */
        assertEq(auction.tokenPrice(), 0.5e6);
        assertFalse(auction.auctionSuccessful());
        assertFalse(auction.auctionEnded());

        /*
            Success when price reach minPrice
        */
        vm.prank(bob);
        auction.commitTokens(bob, 5_000e6);
        assertEq(auction.commitmentsTotal(), 10_000e6);
        assertEq(auction.commitments(bob), 5_000e6);
        assertEq(auction.tokenPrice(), 1e6);
        assertTrue(auction.auctionSuccessful());

        /*
            user commit more than ceiling price, contract return redundant tokens
            Now the contract need 10_000 usdt to complete
        */
        vm.prank(bob);
        vm.expectEmit(true, true, true, true, USDT);
        emit Transfer(bob, address(auction), 10_000e6);
        auction.commitTokens(bob, 15_000e6);
        assertEq(auction.commitmentsTotal(), 20_000e6);
        assertEq(auction.commitments(bob), 15_000e6);
        assertEq(auction.tokenPrice(), 2e6);
        assertTrue(auction.auctionSuccessful());
        assertTrue(auction.auctionEnded());
        assertTrue(auction.finalized());

        /*
            try commit after auction success. Transaction go through but no fund transfer
        */
        uint256 aliceBalance = IERC20(USDT).balanceOf(alice);
        vm.prank(alice);
        auction.commitTokens(alice, 5_000e6);
        assertEq(auction.commitmentsTotal(), 20_000e6);
        assertEq(IERC20(USDT).balanceOf(alice), aliceBalance);

        assertEq(auction.tokensClaimableWithoutVesting(alice), 2_500 ether);
        assertEq(auction.tokensClaimableWithoutVesting(bob), 7_500 ether);
    }

    function test_commit_on_behalf_of_other() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(alice);
        IERC20(USDT).approve(address(auction), type(uint256).max);

        vm.warp(auction.startTime());
        vm.prank(alice);
        auction.commitTokens(bob, 5_000e6);
        assertEq(auction.commitmentsTotal(), 5_000e6);
        assertEq(auction.commitments(bob), 5_000e6);
        assertEq(auction.commitments(alice), 0);
    }

    function test_claim_success_auction() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(alice);
        IERC20(USDT).approve(address(auction), type(uint256).max);

        vm.prank(bob);
        IERC20(USDT).approve(address(auction), type(uint256).max);

        vm.warp(auction.startTime());
        vm.prank(alice);
        auction.commitTokens(alice, 5_000e6);

        /*
            Auto finalize on 500s, vesting started.
            User commit token auto send to treasury
        */
        vm.warp(auction.startTime() + 500);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true, USDT);
        emit Transfer(address(auction), treasury, 20_000e6);
        auction.commitTokens(bob, 15_000e6);

        assertTrue(auction.auctionSuccessful());
        assertTrue(auction.finalized());
        assertEq(auction.vestingStart(), auction.startTime() + 500);
        assertEq(auction.vestingDuration(), 1000);

        assertEq(auction.tokensClaimableWithoutVesting(alice), 2_500 ether);
        assertEq(auction.tokensClaimableWithoutVesting(bob), 7_500 ether);
        assertEq(auction.tokensClaimableWithoutVesting(eve), 0);

        /* vesting end at 1500s. Travel to 1000. Claimable should be an half */
        vm.warp(auction.startTime() + 1000);
        assertEq(auction.tokensClaimableWithoutVesting(alice), 2_500 ether);
        assertEq(auction.tokensClaimable(alice), 1250 ether);
        assertEq(auction.tokensClaimableWithoutVesting(bob), 7_500 ether);
        assertEq(auction.tokensClaimable(bob), 3750 ether);

        /* alice claim LVL */
        vm.prank(alice);
        vm.expectEmit(true, true, true, true, LVL);
        emit Transfer(address(auction), bob, 1250 ether);
        auction.withdrawTokens(bob);

        assertEq(auction.tokensClaimableWithoutVesting(alice), 1250 ether);
        assertEq(auction.tokensClaimable(alice), 0 ether);
        assertEq(auction.tokensClaimableWithoutVesting(bob), 7_500 ether);
        assertEq(auction.tokensClaimable(bob), 3_750 ether);

        /* vesting ended */
        vm.warp(auction.vestingStart() + auction.vestingDuration() + 1);
        assertEq(auction.tokensClaimableWithoutVesting(bob), 7_500 ether);
        assertEq(auction.tokensClaimable(bob), 7_500 ether);
        assertEq(auction.tokensClaimableWithoutVesting(alice), 1250 ether);
        assertEq(auction.tokensClaimable(alice), 1250 ether);
    }

    function test_claim_failed_auction() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(alice);
        IERC20(USDT).approve(address(auction), type(uint256).max);

        vm.prank(bob);
        IERC20(USDT).approve(address(auction), type(uint256).max);

        vm.warp(auction.startTime());
        vm.prank(alice);
        auction.commitTokens(alice, 5_000e6);

        vm.warp(auction.endTime() + 1);

        assertFalse(auction.auctionSuccessful());
        assertFalse(auction.finalized());
        assertTrue(auction.auctionEnded());

        assertEq(auction.tokensClaimable(alice), 0);
        assertEq(auction.tokensClaimable(bob), 0);

        vm.prank(eve);
        vm.expectRevert("!admin");
        auction.finalize();

        vm.prank(admin);
        /* LVL refund to treasury when finalize */
        vm.expectEmit(true, true, true, true, LVL);
        emit Transfer(address(auction), treasury, 10_000 ether);
        auction.finalize();
        assertTrue(auction.finalized());

        vm.prank(alice);
        vm.expectEmit(true, true, true, true, USDT);
        emit Transfer(address(auction), bob, 5_000e6);
        auction.withdrawTokens(bob);
    }

    function test_finalize_failed_auction_open_when_expire() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(alice);
        IERC20(USDT).approve(address(auction), type(uint256).max);

        vm.prank(bob);
        IERC20(USDT).approve(address(auction), type(uint256).max);

        vm.warp(auction.startTime());
        vm.prank(alice);
        auction.commitTokens(alice, 5_000e6);

        vm.warp(auction.endTime() + 1);

        assertFalse(auction.auctionSuccessful());
        assertFalse(auction.finalized());
        assertTrue(auction.auctionEnded());

        vm.prank(eve);
        vm.expectRevert("!admin");
        auction.finalize();

        vm.warp(auction.endTime() + 7 days + 1);
        vm.prank(eve);
        auction.finalize();
        assertTrue(auction.finalized());
    }

    function test_cancel_auction() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(eve);
        vm.expectRevert("!admin");
        auction.cancelAuction();

        // refund LVL to treasury when cancel
        vm.prank(admin);
        vm.expectEmit(true, true, true, true, LVL);
        emit Transfer(address(auction), treasury, 10_000 ether);
        auction.cancelAuction();
    }

    function test_cannot_cancel_or_reset_params_when_user_commit() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();
        vm.prank(alice);
        IERC20(USDT).approve(address(auction), 1000e6);

        vm.warp(auction.startTime());
        vm.prank(alice);
        auction.commitTokens(alice, 5e6);

        vm.prank(admin);
        vm.expectRevert(bytes("auction started"));
        auction.cancelAuction();

        vm.prank(admin);
        vm.expectRevert(bytes("auction started"));
        auction.setAuctionTime(1100, 1200);

        vm.prank(admin);
        vm.expectRevert(bytes("auction started"));
        auction.setAuctionPrice(1100, 0);
    }

    function test_set_treasury() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(eve);
        vm.expectRevert("!admin");
        auction.setAuctionTreasury(eve);

        vm.prank(admin);
        vm.expectRevert("address = 0");
        auction.setAuctionTreasury(address(0));

        vm.prank(admin);
        auction.setAuctionTreasury(address(1));
        assertEq(auction.auctionTreasury(), address(1));
    }

    function test_set_auction_time() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(eve);
        vm.expectRevert("!admin");
        auction.setAuctionTime(1100, 1200);

        vm.prank(admin);
        vm.expectRevert("start time < current time");
        auction.setAuctionTime(900, 1100);

        vm.prank(admin);
        vm.expectRevert("end time < start time");
        auction.setAuctionTime(1230, 1100);

        vm.prank(admin);
        vm.expectRevert("unix timestamp in seconds");
        auction.setAuctionTime(10000000000000, 1);

        vm.prank(admin);
        vm.expectRevert("unix timestamp in seconds");
        auction.setAuctionTime(100, 100000000000000000);

        vm.prank(admin);
        auction.setAuctionTime(1100, 1200);
        assertEq(auction.startTime(), 1100);
        assertEq(auction.endTime(), 1200);
    }

    function test_set_auction_price() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(eve);
        vm.expectRevert("!admin");
        auction.setAuctionPrice(1100, 100);

        vm.prank(admin);
        vm.expectRevert("ceiling price < minimum price");
        auction.setAuctionPrice(1000, 1100);

        vm.prank(admin);
        vm.expectRevert("ceiling price < minimum ceiling price");
        auction.setAuctionPrice(1, 0);

        vm.prank(admin);
        auction.setAuctionPrice(1200, 1);
        assertEq(auction.ceilingPrice(), 1200);
        assertEq(auction.minPrice(), 1);
    }

    function test_transfer_admin() external {
        vm.warp(1000);
        LvlBatchAuction auction = initAuction();

        vm.prank(eve);
        vm.expectRevert("!admin");
        auction.transferAdmin(eve);

        vm.prank(admin);
        auction.transferAdmin(address(2));
        assertEq(auction.admin(), address(2));
    }
}
