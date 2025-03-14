pragma solidity =0.8.28;
import "forge-std/Test.sol";
import "../src/UniswapV2Factory.sol";
import "./MockERC20.sol";

contract UniswapV2FactoryTest is Test {
    UniswapV2Factory factory;
    MockERC20 tokenA;
    MockERC20 tokenB;
    address feeToSetter = address(0x1);

    function setUp() public {
        factory = new UniswapV2Factory(feeToSetter);
        tokenA = new MockERC20(1000);
        tokenB = new MockERC20(1000);
    }

    function testCreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.allPairs(0), pair);
        assertEq(factory.allPairsLength(), 1);
    }

    function testCreateDuplicatePair() public {
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert("UniswapV2: PAIR_EXISTS");
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testSetFeeTo() public {
        vm.prank(feeToSetter);
        factory.setFeeTo(address(0x2));
        assertEq(factory.feeTo(), address(0x2));
    }

    function testSetFeeToUnauthorized() public {
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeTo(address(0x2));
    }
}