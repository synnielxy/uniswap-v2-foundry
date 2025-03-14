pragma solidity =0.8.28;
import "forge-std/Test.sol";
import "../src/UniswapV2Pair.sol";
import "../src/UniswapV2Factory.sol";
import "./MockERC20.sol";

contract UniswapV2PairTest is Test {
    UniswapV2Factory factory;
    MockERC20 tokenA;
    MockERC20 tokenB;
    UniswapV2Pair pair;
    uint256 constant INITIAL_AMOUNT = 1000 ether;

    function setUp() public {
        factory = new UniswapV2Factory(address(this));
        tokenA = new MockERC20(INITIAL_AMOUNT);
        tokenB = new MockERC20(INITIAL_AMOUNT);
        address pairAddr = factory.createPair(address(tokenA), address(tokenB));
        pair = UniswapV2Pair(pairAddr);
        tokenA.approve(address(pair), type(uint256).max);
        tokenB.approve(address(pair), type(uint256).max);
    }

    function testMint() public {
        tokenA.transfer(address(pair), 1 ether);
        tokenB.transfer(address(pair), 1 ether);
        pair.mint(address(this));
        assertEq(pair.balanceOf(address(this)), 1 ether - 1000); // MINIMUM_LIQUIDITY
        assertEq(pair.totalSupply(), 1 ether);
    }

    function testBurn() public {
        // 获取实际的初始余额
        uint256 actualInitialBalanceA = tokenA.balanceOf(address(this));
        uint256 actualInitialBalanceB = tokenB.balanceOf(address(this));
        
        // 添加流动性
        tokenA.transfer(address(pair), 1 ether);
        tokenB.transfer(address(pair), 1 ether);
        uint liquidity = pair.mint(address(this));
        
        // 获取总供应量
        uint256 totalSupply = pair.totalSupply();
        
        // 销毁流动性
        pair.transfer(address(pair), liquidity);
        pair.burn(address(this));
        
        // 使用与合约完全相同的计算逻辑
        uint256 expectedAmountA = 1 ether * liquidity / totalSupply;
        uint256 expectedAmountB = 1 ether * liquidity / totalSupply;
        
        // 使用实际初始余额计算预期最终余额
        uint256 expectedBalanceA = actualInitialBalanceA - 1 ether + expectedAmountA;
        uint256 expectedBalanceB = actualInitialBalanceB - 1 ether + expectedAmountB;
        
        assertEq(tokenA.balanceOf(address(this)), expectedBalanceA);
        assertEq(tokenB.balanceOf(address(this)), expectedBalanceB);
    }

    function testSwap() public {
        // 获取实际的初始余额
        uint256 actualInitialBalanceA = tokenA.balanceOf(address(this));
        uint256 actualInitialBalanceB = tokenB.balanceOf(address(this));
        
        // 添加流动性：2 ether 每个代币
        tokenA.transfer(address(pair), 2 ether);
        tokenB.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        // 转入 0.1 ether 的 tokenA 进行交换
        tokenA.transfer(address(pair), 0.1 ether);

        // 计算精确的输出金额
        // amountIn = 0.1 ether
        // reserveIn = 2 ether
        // reserveOut = 2 ether
        // amountInWithFee = amountIn * 997
        // numerator = amountInWithFee * reserveOut
        // denominator = (reserveIn * 1000) + amountInWithFee
        uint amountIn = 0.1 ether;
        uint reserveIn = 2 ether;
        uint reserveOut = 2 ether;
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        uint amountOut = numerator / denominator;

        // 执行交换
        pair.swap(0, amountOut, address(this), "");
        
        // 计算预期余额：初始金额 - 投入流动性 - 交易投入 + 交易输出
        uint256 expectedBalanceA = actualInitialBalanceA - 2 ether - 0.1 ether;
        uint256 expectedBalanceB = actualInitialBalanceB - 2 ether + amountOut;
        
        assertEq(tokenA.balanceOf(address(this)), expectedBalanceA);
        assertEq(tokenB.balanceOf(address(this)), expectedBalanceB);
    }
}