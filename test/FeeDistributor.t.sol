// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {WETH9} from "./mocks/WETH.sol";
import {MockPool} from "./mocks/MockPool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ETHUnwrapper} from "./mocks/ETHUnwrapper.sol";
import "../src/utils/FeeDistributor.sol";

contract FeeDistributorTest is Test {
    address owner = 0xCE2ee0D3666342d263F534e9375c1A450AC7624d;
    address treasury = 0xA6Cc2e3d88e0B510C1c0157F867a6294d2FAB0F1;
    address llpReward = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;
    address devFund = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;

    uint256 public constant PRECISION = 1e6;

    FeeDistributor feeDistributor;
    MockPool pool;

    MockERC20 usdc;

    WETH9 weth;
    ETHUnwrapper ethUnwrapper;

    address[] feeTokens = new address[](2);

    function setUp() external {
        vm.startPrank(owner);

        usdc = new MockERC20("USDC", "USDC", 18);
        weth = new WETH9();

        pool = new MockPool();
        ethUnwrapper = new ETHUnwrapper(address(weth));

        vm.deal(owner, 1 ether);
        weth.deposit{value: 1 ether}();
        weth.transfer(address(pool), 1 ether);

        usdc.mintTo(1 ether, address(pool));

        pool.setFeeReserve(address(weth), 1 ether);
        pool.setFeeReserve(address(usdc), 1 ether);

        feeTokens[0] = address(usdc);
        feeTokens[1] = address(weth);

        feeDistributor = new FeeDistributor(address(pool), new address[](0));

        vm.stopPrank();
    }

    function testWithdrawFee() external {
        vm.startPrank(owner);
        // Withdraw fee before config tokens
        {
            vm.expectRevert();
            feeDistributor.withdrawFee();
            assertEq(usdc.balanceOf(address(pool)), 1 ether);
            assertEq(usdc.balanceOf(address(feeDistributor)), 0 ether);
        }
        // Withdraw fee after config tokens
        {
            feeDistributor.setFeeTokens(feeTokens);
            vm.expectRevert();
            feeDistributor.withdrawFee();
            assertEq(usdc.balanceOf(address(pool)), 1 ether);
            assertEq(usdc.balanceOf(address(feeDistributor)), 0 ether);
        }
        // Withdraw before set recipient
        {
            feeDistributor.setFeeTokens(feeTokens);
            feeDistributor.setRecipient(address(treasury), 0);
            feeDistributor.setRecipient(address(llpReward), 0);
            vm.expectRevert();
            feeDistributor.withdrawFee();
        }
        // Withdraw after set recipient
        {
            feeDistributor.setRecipient(address(treasury), PRECISION);
            feeDistributor.setRecipient(address(llpReward), PRECISION * 2);
            feeDistributor.withdrawFee();
            assertEq(usdc.balanceOf(address(pool)), 0);
            assertEq(usdc.balanceOf(address(feeDistributor)), 0);
            assertEq(usdc.balanceOf(treasury), 1 ether * PRECISION / (PRECISION * 3));
            assertEq(usdc.balanceOf(treasury) + usdc.balanceOf(llpReward), 1 ether);
        }
        // Withdraw after set recipient = 0
        {
            feeDistributor.setFeeTokens(feeTokens);
            feeDistributor.setRecipient(address(treasury), 0);
            feeDistributor.setRecipient(address(llpReward), 0);
            vm.expectRevert();
            feeDistributor.withdrawFee();
        }
        // Withdraw after set pause
        {
            feeDistributor.pause();
            feeDistributor.setRecipient(address(treasury), PRECISION);
            feeDistributor.setRecipient(address(llpReward), PRECISION * 2);
            vm.expectRevert("Pausable: paused");
            feeDistributor.withdrawFee();
        }

        vm.stopPrank();
    }

    function testSetRecipient() external {
        // set recipient but missing owner role
        {
            vm.startPrank(treasury);
            vm.expectRevert("Ownable: caller is not the owner");
            feeDistributor.setRecipient(address(treasury), PRECISION);
            vm.stopPrank();
        }
        vm.startPrank(owner);
        // set recipient
        {
            feeDistributor.setRecipient(address(treasury), PRECISION);
            feeDistributor.setRecipient(address(llpReward), PRECISION * 2);
            assertEq(feeDistributor.totalWeight(), PRECISION * 3);
        }
        // update recipient
        {
            feeDistributor.setRecipient(address(treasury), PRECISION);
            feeDistributor.setRecipient(address(llpReward), 0);
            assertEq(feeDistributor.totalWeight(), PRECISION);
        }
        vm.stopPrank();
    }

    function testRemoveRecipient() external {
        // remove recipient but missing owner role
        {
            vm.startPrank(treasury);
            vm.expectRevert("Ownable: caller is not the owner");
            feeDistributor.removeRecipient(treasury);
            vm.stopPrank();
        }
        vm.startPrank(owner);
        // remove not exits recipient
        {
            vm.expectRevert();
            feeDistributor.removeRecipient(treasury);
            assertEq(feeDistributor.totalWeight(), 0);
        }
        // remove exits recipient
        {
            feeDistributor.setRecipient(address(treasury), PRECISION);
            feeDistributor.removeRecipient(treasury);
            assertEq(feeDistributor.totalWeight(), 0);
        }
    }

    function testRole() external {
        {
            vm.startPrank(treasury);
            vm.expectRevert("Ownable: caller is not the owner");
            feeDistributor.setRecipient(address(treasury), PRECISION);
            vm.expectRevert("Ownable: caller is not the owner");
            feeDistributor.removeRecipient(treasury);
            vm.expectRevert("Ownable: caller is not the owner");
            feeDistributor.pause();
            vm.expectRevert("Ownable: caller is not the owner");
            feeDistributor.unpause();
            vm.stopPrank();
        }
        {
            vm.startPrank(owner);
            feeDistributor.setRecipient(address(treasury), PRECISION);
            feeDistributor.removeRecipient(treasury);
            feeDistributor.pause();
            feeDistributor.unpause();
            vm.stopPrank();
        }
    }
}
