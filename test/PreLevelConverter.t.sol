pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "src/vesting/PreLevelConverter.sol";
import "src/interfaces/IBurnableERC20.sol";
import "src/tokens/PreLevelToken.sol";
import "./mocks/MockERC20.sol";

contract PreLevelConverterTest is Test {
    function test_convert_pre_lvl_on_arbitrum() external {
        vm.createSelectFork("arbitrum", 119574036);
        address proxyAdmin = address(bytes20("proxyAdmin"));
        address daoTreasury = address(bytes20("daoTreasury"));
        PreLevelToken preLVL = new PreLevelToken();
        address lvl = 0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149;
        address usdt = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        address pool = 0x32B7bF19cb8b95C27E644183837813d4b595dcc6;
        address lvlUsdtUniV2Pair = 0xc11cFF8A44853A5B3F24a7F4B817E6e64fbEBA2a;
        IBurnableERC20[] memory lp = new IBurnableERC20[](3);
        lp[0] = IBurnableERC20(0x5573405636F4b895E511C9C54aAfbefa0E7Ee458);
        lp[1] = IBurnableERC20(0xb076f79f8D1477165E2ff8fa99930381FB7d94c1);
        lp[2] = IBurnableERC20(0x502697AF336F7413Bb4706262e7C506Edab4f3B9);

        Proxy proxy = new Proxy(
            address(new PreLevelConverter()),
            proxyAdmin,
            new bytes(0)
        );

        PreLevelConverter sut = PreLevelConverter(address(proxy));
        sut.initialize({
            _lvl: address(lvl),
            _preLvl: address(preLVL),
            _usdt: address(usdt),
            _daoTreasury: daoTreasury,
            _pool: pool,
            _lvlUsdtUniV2Pair: lvlUsdtUniV2Pair,
            _taxRate: 3e5,
            _missingDecimal: 12,
            _llpTokens: lp
        });

        address reporter = address(bytes20("reporter"));
        sut.setPriceReporter(reporter);
        vm.warp(block.timestamp + 1);
        console.log("TWAP", sut.getReferenceTWAP());

        vm.prank(reporter);
        sut.updateTWAP(2.3e6, block.timestamp);

        address alice = address(bytes20("alice"));
        deal(lvl, address(sut), 100_000 ether);
        deal(address(preLVL), address(alice), 10 ether);
        deal(usdt, address(alice), 100e6);

        vm.startPrank(alice);
        IBurnableERC20(lvl).approve(address(sut), type(uint256).max);
        preLVL.approve(address(sut), type(uint256).max);
        IBurnableERC20(usdt).approve(address(sut), type(uint256).max);
        uint256 gas = gasleft();
        sut.convert(10 ether, 7.5e6, address(alice), block.timestamp);
        console.log("gas used", gas - gasleft());
    }

    function test_convert_pre_lvl_on_bsc() external {
        vm.createSelectFork("bsc", 30691158);
        address proxyAdmin = address(bytes20("proxyAdmin"));
        address daoTreasury = address(bytes20("daoTreasury"));
        PreLevelToken preLVL = new PreLevelToken();
        address lvl = 0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149;
        address usdt = 0x55d398326f99059fF775485246999027B3197955;
        address pool = 0xA5aBFB56a78D2BD4689b25B8A77fd49Bb0675874;
        address lvlUsdtUniV2Pair = 0x69d6B9a5709eEad2C6568c1F636B32707eA55A7e;
        IBurnableERC20[] memory lp = new IBurnableERC20[](3);
        lp[0] = IBurnableERC20(0xB5C42F84Ab3f786bCA9761240546AA9cEC1f8821);
        lp[1] = IBurnableERC20(0x4265af66537F7BE1Ca60Ca6070D97531EC571BDd);
        lp[2] = IBurnableERC20(0xcC5368f152453D497061CB1fB578D2d3C54bD0A0);

        Proxy proxy = new Proxy(
            address(new PreLevelConverter()),
            proxyAdmin,
            new bytes(0)
        );

        PreLevelConverter sut = PreLevelConverter(address(proxy));
        sut.initialize({
            _lvl: address(lvl),
            _preLvl: address(preLVL),
            _usdt: address(usdt),
            _daoTreasury: daoTreasury,
            _pool: pool,
            _lvlUsdtUniV2Pair: lvlUsdtUniV2Pair,
            _taxRate: 3e5,
            _missingDecimal: 12,
            _llpTokens: lp
        });

        address reporter = address(bytes20("reporter"));
        sut.setPriceReporter(reporter);
        vm.warp(block.timestamp + 1);
        console.log("TWAP", sut.getReferenceTWAP());

        vm.prank(reporter);
        sut.updateTWAP(2.3e6, block.timestamp);

        address alice = address(bytes20("alice"));
        deal(lvl, address(sut), 100_000 ether);
        deal(address(preLVL), address(alice), 10 ether);
        deal(usdt, address(alice), 100e6);

        vm.startPrank(alice);
        IBurnableERC20(lvl).approve(address(sut), type(uint256).max);
        preLVL.approve(address(sut), type(uint256).max);
        IBurnableERC20(usdt).approve(address(sut), type(uint256).max);
        uint256 gas = gasleft();
        sut.convert(10 ether, 7.5e6, address(alice), block.timestamp);
        console.log("gas used", gas - gasleft());
    }
}
