pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "../src/treasury/LGOView.sol";

contract LGOViewTest is Test {
    address owner = address(bytes20("owner"));
    address alice = address(bytes20("alice"));

    MockERC20 LGO;

    LGOView lgoView;

    function setUp() external {
        vm.warp(0);
        vm.startPrank(owner);
        LGO = new MockERC20("LGO", "LGO", 18);
        lgoView = new LGOView(address(LGO), 100 ether);

        LGO.mint(1000 ether);

        vm.stopPrank();
    }

    function test_estimated_circulating_supply() external {
        assertEq(lgoView.totalEmission(), 100 ether);
        assertEq(lgoView.estimatedLGOCirculatingSupply(), 100 ether);
    }

    function test_add_emission_revert_owner() external {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LGOView.Unauthorized.selector));
        lgoView.addEmission(100 ether);
    }

    function test_add_emission_success() external {
        vm.prank(owner);
        lgoView.addEmission(100 ether);
        assertEq(lgoView.totalEmission(), 200 ether);
        assertEq(lgoView.estimatedLGOCirculatingSupply(), 200 ether);
    }

    function test_burn_success() external {
        vm.prank(owner);
        LGO.burn(10 ether);
        assertEq(lgoView.totalEmission(), 100 ether);
        assertEq(lgoView.estimatedLGOCirculatingSupply(), 90 ether);
    }
}
