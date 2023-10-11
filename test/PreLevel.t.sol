// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/tokens/PreLevelToken.sol";

contract PreLevelTokenTest is Test {
    PreLevelToken token;
    address owner = address(bytes20("owner"));
    address alice = address(bytes20("alice"));
    address eve = address(bytes20("eve"));

    function setUp() external {
        vm.startPrank(owner);
        token = new PreLevelToken();
        assertEq(token.owner(), owner);
        vm.stopPrank();
    }

    function test_set_minter() external {
        vm.prank(alice);
        vm.expectRevert();
        token.setMinter(alice);

        vm.prank(owner);
        token.setMinter(alice);
        assertEq(token.minter(), alice);
    }

    function test_mint() external {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1000e18);

        vm.prank(owner);
        token.setMinter(alice);

        vm.prank(alice);
        token.mint(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
    }
}
