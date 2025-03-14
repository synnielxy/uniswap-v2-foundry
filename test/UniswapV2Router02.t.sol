// test/UniswapV2Router02.t.sol
pragma solidity =0.8.28;
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/UniswapV2Router02.sol";
import "../src/UniswapV2Factory.sol";
import "./MockERC20.sol";
import "./MockWETH.sol";

contract UniswapV2Router02Test is Test {
    UniswapV2Factory factory;
    UniswapV2Router02 router;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockWETH weth;

    function setUp() public {
        factory = new UniswapV2Factory(address(this));
        weth = new MockWETH();
        router = new UniswapV2Router02(address(factory), address(weth));
        
        // Mint more tokens to ensure enough liquidity
        tokenA = new MockERC20(1000 ether);
        tokenB = new MockERC20(1000 ether);
        
        // Ensure the test contract has enough ETH for testing
        vm.deal(address(this), 100 ether);
        
        // Approve the router to use the tokens
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        
        // Ensure WETH is also approved 
        weth.approve(address(router), type(uint256).max);
    }

    function testAddLiquidity() public {
        uint amountA = 10 ether;
        uint amountB = 10 ether;
        
        // Ensure the test contract has enough tokens
        assertGe(tokenA.balanceOf(address(this)), amountA, "Not enough tokenA");
        assertGe(tokenB.balanceOf(address(this)), amountB, "Not enough tokenB");
        
        (uint actualA, uint actualB, uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,  // Allow any amount of tokenA
            0,  // Allow any amount of tokenB
            address(this),
            block.timestamp + 100
        );
        
        // Verify the results
        assertGt(actualA, 0, "No tokenA added");
        assertGt(actualB, 0, "No tokenB added");
        assertGt(liquidity, 0, "No liquidity received");
        
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "Pair not created");
    }

    function testSwapExactTokensForTokens() public {
        // Add liquidity first
        uint amountA = 100 ether;
        uint amountB = 100 ether;
        
        router.addLiquidity(
            address(tokenA), 
            address(tokenB), 
            amountA, 
            amountB, 
            0, 
            0, 
            address(this), 
            block.timestamp + 100
        );
        
        // Record the balance before the swap
        uint initialBalanceB = tokenB.balanceOf(address(this));
        
        // Prepare the swap path
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        // Execute the swap
        uint amountIn = 1 ether;
        uint[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            0,  // Accept any amount of output tokens
            path,
            address(this),
            block.timestamp + 100
        );
        
        // Verify the results
        assertGt(amounts[1], 0, "No output tokens received");
        assertGt(tokenB.balanceOf(address(this)), initialBalanceB, "Balance of tokenB did not increase");
    }

    function testRemoveLiquidity() public {
        // Add liquidity first
        uint amountA = 100 ether;
        uint amountB = 100 ether;
        
        (uint addedA, uint addedB, uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp + 100
        );
        
        // Verify liquidity addition
        assertGt(addedA, 0, "No tokenA added");
        assertGt(addedB, 0, "No tokenB added");
        assertGt(liquidity, 0, "No liquidity received");
        
        // Record initial balances
        uint initialBalanceA = tokenA.balanceOf(address(this));
        uint initialBalanceB = tokenB.balanceOf(address(this));
        
        // Only remove part of the liquidity (90%) to avoid rounding errors
        uint liquidityToRemove = liquidity * 9 / 10;
        
        // Need to approve the router to use the LP tokens
        address pair = factory.getPair(address(tokenA), address(tokenB));
        IERC20(pair).approve(address(router), liquidityToRemove);
        
        // Remove liquidity
        (uint removedA, uint removedB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidityToRemove,
            0, // amountAMin
            0, // amountBMin
            address(this),
            block.timestamp + 100
        );
        
        // Verify liquidity removal
        assertGt(removedA, 0, "No tokenA removed");
        assertGt(removedB, 0, "No tokenB removed");
        
        // Check if the balances increased
        assertGt(tokenA.balanceOf(address(this)), initialBalanceA, "TokenA balance did not increase");
        assertGt(tokenB.balanceOf(address(this)), initialBalanceB, "TokenB balance did not increase");
        
        // Check if the pair still exists
        assertTrue(pair != address(0), "Pair was destroyed");
    }

    function testSwapETHForExactTokens() public {
        // Add liquidity with ETH and tokenB
        uint tokenAmount = 100 ether;
        
        // Add liquidity with ETH
        router.addLiquidityETH{value: 10 ether}(
            address(tokenB),
            tokenAmount,
            0,  // amountTokenMin
            0,  // amountETHMin
            address(this),
            block.timestamp + 100
        );
        
        // Record the balance before swap
        uint initialBalanceB = tokenB.balanceOf(address(this));
        
        // Prepare the swap path
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenB);
        
        // Define the exact amount of tokens we want to receive
        uint amountOut = 1 ether;
        
        // Execute the swap - we're willing to spend up to 5 ETH to get exactly 1 tokenB
        uint[] memory amounts = router.swapETHForExactTokens{value: 5 ether}(
            amountOut,
            path,
            address(this),
            block.timestamp + 100
        );
        
        // Verify the results
        assertEq(tokenB.balanceOf(address(this)) - initialBalanceB, amountOut, "Did not receive exact tokens");
        assertGt(amounts[0], 0, "No ETH spent");
        assertEq(amounts[1], amountOut, "Output amount doesn't match requested amount");
        
        // The router should refund excess ETH, so we should have received some ETH back
        assertLt(amounts[0], 5 ether, "All ETH was spent, which suggests no refund occurred");
    }

    function testSwapTokensForExactTokens() public {
        // Add liquidity first
        uint amountA = 100 ether;
        uint amountB = 100 ether;
        
        router.addLiquidity(
            address(tokenA), 
            address(tokenB), 
            amountA, 
            amountB, 
            0, 
            0, 
            address(this), 
            block.timestamp + 100
        );
        
        // Record the balance before the swap
        uint initialBalanceA = tokenA.balanceOf(address(this));
        uint initialBalanceB = tokenB.balanceOf(address(this));
        
        // Prepare the swap path
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        // Define the exact amount of tokens we want to receive
        uint amountOut = 1 ether;
        // Define the maximum amount we're willing to pay
        uint maxAmountIn = 5 ether;
        
        // Execute the swap
        uint[] memory amounts = router.swapTokensForExactTokens(
            amountOut,
            maxAmountIn,
            path,
            address(this),
            block.timestamp + 100
        );
        
        // Verify the results
        assertEq(tokenB.balanceOf(address(this)) - initialBalanceB, amountOut, "Did not receive exact tokens");
        assertGt(amounts[0], 0, "No input tokens spent");
        assertEq(amounts[1], amountOut, "Output amount doesn't match requested amount");
        assertLe(amounts[0], maxAmountIn, "More than maximum input was spent");
        assertEq(initialBalanceA - tokenA.balanceOf(address(this)), amounts[0], "Token A balance change doesn't match the input amount");
    }

    function testSwapExactETHForTokens() public {
        // Add liquidity with ETH and tokenB
        uint tokenAmount = 100 ether;
        
        // Add liquidity with ETH
        router.addLiquidityETH{value: 10 ether}(
            address(tokenB),
            tokenAmount,
            0,  // amountTokenMin
            0,  // amountETHMin
            address(this),
            block.timestamp + 100
        );
        
        // Record balance before swap
        uint initialBalanceB = tokenB.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;
        
        // Prepare the swap path
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenB);
        
        // Amount of ETH to swap
        uint amountETHIn = 1 ether;
        
        // Execute the swap with exact ETH input
        uint[] memory amounts = router.swapExactETHForTokens{value: amountETHIn}(
            0,  // Accept any amount of output tokens (minimum)
            path,
            address(this),
            block.timestamp + 100
        );
        
        // Verify the results
        assertEq(amounts[0], amountETHIn, "ETH input amount doesn't match");
        assertGt(amounts[1], 0, "No tokens received");
        assertGt(tokenB.balanceOf(address(this)), initialBalanceB, "Balance of tokenB did not increase");
        assertEq(tokenB.balanceOf(address(this)) - initialBalanceB, amounts[1], "Token balance change doesn't match output amount");
        assertEq(initialETHBalance - address(this).balance, amountETHIn, "ETH balance didn't decrease by correct amount");
    }

    function testSwapTokensForExactETH() public {
        // Add liquidity with tokenA and ETH
        uint tokenAmount = 100 ether;
        
        // Add liquidity with ETH
        router.addLiquidityETH{value: 10 ether}(
            address(tokenA),
            tokenAmount,
            0,  // amountTokenMin
            0,  // amountETHMin
            address(this),
            block.timestamp + 100
        );
        
        // Record balances before swap
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;
        
        // Prepare the swap path
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);
        
        // Define the exact amount of ETH we want to receive
        uint amountETHOut = 1 ether;
        // Maximum amount of tokens we're willing to spend - increased to allow for price impact
        uint maxTokensIn = 20 ether;
        
        // Approve the router to spend our tokens
        tokenA.approve(address(router), maxTokensIn);
        
        // Execute the swap
        uint[] memory amounts = router.swapTokensForExactETH(
            amountETHOut,  // Exact ETH output
            maxTokensIn,   // Maximum tokens input
            path,
            address(this),
            block.timestamp + 100
        );
        
        // Verify the results
        assertEq(address(this).balance - initialETHBalance, amountETHOut, "Did not receive exact ETH amount");
        assertGt(amounts[0], 0, "No tokens spent");
        assertEq(amounts[1], amountETHOut, "ETH output amount doesn't match requested amount");
        assertLe(amounts[0], maxTokensIn, "More than maximum tokens were spent");
        assertEq(initialTokenBalance - tokenA.balanceOf(address(this)), amounts[0], "Token balance change doesn't match the input amount");
    }

    function testSwapExactTokensForETH() public {
        // Add liquidity with tokenA and ETH
        uint tokenAmount = 100 ether;
        
        // Add liquidity with ETH
        router.addLiquidityETH{value: 10 ether}(
            address(tokenA),
            tokenAmount,
            0,  // amountTokenMin
            0,  // amountETHMin
            address(this),
            block.timestamp + 100
        );
        
        // Record balances before swap
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;
        
        // Prepare the swap path
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);
        
        // Define the exact amount of tokens we want to spend
        uint amountTokensIn = 5 ether;
        
        // Approve the router to spend our tokens
        tokenA.approve(address(router), amountTokensIn);
        
        // Execute the swap
        uint[] memory amounts = router.swapExactTokensForETH(
            amountTokensIn, // Exact tokens input
            0,              // Accept any amount of ETH (minimum)
            path,
            address(this),
            block.timestamp + 100
        );
        
        // Verify the results
        assertEq(initialTokenBalance - tokenA.balanceOf(address(this)), amountTokensIn, "Did not spend exact token amount");
        assertEq(amounts[0], amountTokensIn, "Token input amount doesn't match");
        assertGt(amounts[1], 0, "No ETH received");
        assertGt(address(this).balance, initialETHBalance, "ETH balance did not increase");
        assertEq(address(this).balance - initialETHBalance, amounts[1], "ETH balance change doesn't match the output amount");
    }
    
    function testRemoveLiquidityETH() public {
        // Add liquidity first with ETH and tokenA
        uint tokenAmount = 100 ether;
        uint ethAmount = 10 ether;
        
        // Record initial balances
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;
        
        // Add liquidity with ETH
        (uint addedToken, uint addedETH, uint liquidity) = router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,  // amountTokenMin
            0,  // amountETHMin
            address(this),
            block.timestamp + 100
        );
        
        // Verify liquidity addition
        assertGt(addedToken, 0, "No token added");
        assertGt(addedETH, 0, "No ETH added");
        assertGt(liquidity, 0, "No liquidity received");
        
        // Need to approve the router to use the LP tokens
        address pair = factory.getPair(address(tokenA), address(weth));
        IERC20(pair).approve(address(router), liquidity);
        
        // Only remove part of the liquidity (90%) to avoid rounding errors
        uint liquidityToRemove = liquidity * 9 / 10;
        
        // Remove liquidity ETH
        (uint removedToken, uint removedETH) = router.removeLiquidityETH(
            address(tokenA),
            liquidityToRemove,
            0, // amountTokenMin
            0, // amountETHMin
            address(this),
            block.timestamp + 100
        );
        
        // Verify liquidity removal
        assertGt(removedToken, 0, "No token removed");
        assertGt(removedETH, 0, "No ETH removed");
        
        // Check if the balances increased
        assertGt(tokenA.balanceOf(address(this)), initialTokenBalance - addedToken, "Token balance not increased after removal");
        assertGt(address(this).balance, initialETHBalance - addedETH, "ETH balance not increased after removal");
    }

    function testRemoveLiquidityWithPermit() public {
        // Add liquidity first
        uint amountA = 100 ether;
        uint amountB = 100 ether;
        
        (,, uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp + 100
        );
        
        // Record initial balances
        uint initialBalanceA = tokenA.balanceOf(address(this));
        uint initialBalanceB = tokenB.balanceOf(address(this));
        
        // Only remove part of the liquidity (90%) to avoid rounding errors
        uint liquidityToRemove = liquidity * 9 / 10;
        
        // Get the pair address
        address pair = factory.getPair(address(tokenA), address(tokenB));
        
        // Generate private key for signing and derive the address
        uint256 privateKey = 0x1234; // An arbitrary private key for testing
        address owner = vm.addr(privateKey);
        
        // Transfer liquidity to the owner address we'll use with permit
        IERC20(pair).transfer(owner, liquidityToRemove);
        
        // Create permit signature components
        uint deadline = block.timestamp + 100;
        
        // Use vm.prank to set msg.sender for the next call
        // and vm.sign to create signature with our privateKey
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IUniswapV2Pair(pair).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                            owner,
                            address(router),
                            liquidityToRemove,
                            IUniswapV2Pair(pair).nonces(owner),
                            deadline
                        )
                    )
                )
            )
        );
        
        // Execute removeLiquidityWithPermit as owner
        vm.startPrank(owner);
        (uint removedA, uint removedB) = router.removeLiquidityWithPermit(
            address(tokenA),
            address(tokenB),
            liquidityToRemove,
            0, // amountAMin
            0, // amountBMin
            owner,
            deadline,
            false, // Not approveMax
            v, r, s
        );
        vm.stopPrank();
        
        // Verify liquidity removal
        assertGt(removedA, 0, "No tokenA removed");
        assertGt(removedB, 0, "No tokenB removed");
        
        // Verify tokens were received by the owner
        assertGt(tokenA.balanceOf(owner), 0, "Owner did not receive tokenA");
        assertGt(tokenB.balanceOf(owner), 0, "Owner did not receive tokenB");
    }

    function _createPermitSignature(
        address pair,
        address owner,
        uint256 liquidity,
        uint256 deadline
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        uint privateKey = 0xBEEF;
        
        bytes32 domainSeparator = UniswapV2ERC20(pair).DOMAIN_SEPARATOR();
        bytes32 permitTypeHash = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        
        bytes32 structHash = keccak256(
            abi.encode(
                permitTypeHash,
                owner,
                address(router),
                liquidity,
                UniswapV2ERC20(pair).nonces(owner),
                deadline
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );
        
        return vm.sign(privateKey, digest);
    }

    function testRemoveETHLiquidityWithPermit() public {
        // Setup - similar to other liquidity tests
        uint tokenAmount = 1 ether;
        uint ethAmount = 4 ether;
        
        // Add liquidity first
        tokenB.approve(address(router), tokenAmount);
        router.addLiquidityETH{value: ethAmount}(
            address(tokenB),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
        
        // Get the pair and LP token amount
        address pair = factory.getPair(address(tokenB), address(weth));
        uint liquidity = IERC20(pair).balanceOf(address(this));
        
        uint privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);
        uint deadline = block.timestamp + 60;
        
        // Transfer LP tokens to owner
        IERC20(pair).transfer(owner, liquidity);
        
        // Use helper function to create signature
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(pair, owner, liquidity, deadline);
        
        // Record balances before removal
        uint tokenBefore = tokenB.balanceOf(owner);
        uint ethBefore = owner.balance;
        
        // Execute removeLiquidityETHWithPermit as the owner
        vm.startPrank(owner);
        router.removeLiquidityETHWithPermit(
            address(tokenB),
            liquidity,
            0,
            0,
            owner,
            deadline,
            false, // approveMax
            v,
            r,
            s
        );
        vm.stopPrank();
        
        // Verify balances increased
        assertGt(tokenB.balanceOf(owner), tokenBefore, "Token balance should increase");
        assertGt(owner.balance, ethBefore, "ETH balance should increase");
        assertEq(IERC20(pair).balanceOf(owner), 0, "All LP tokens should be burned");
    }
    
    function testRemoveLiquidityETHSupportingFeeOnTransferTokens() public {
        // Add liquidity first with ETH and tokenA
        uint tokenAmount = 100 ether;
        uint ethAmount = 10 ether;
        
        // Record initial balances
        uint initialTokenBalance = tokenA.balanceOf(address(this));
        uint initialETHBalance = address(this).balance;
        
        // Add liquidity with ETH
        (uint addedToken, uint addedETH, uint liquidity) = router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,  // amountTokenMin
            0,  // amountETHMin
            address(this),
            block.timestamp + 100
        );
        
        // Verify liquidity addition
        assertGt(addedToken, 0, "No token added");
        assertGt(addedETH, 0, "No ETH added");
        assertGt(liquidity, 0, "No liquidity received");
        
        // Need to approve the router to use the LP tokens
        address pair = factory.getPair(address(tokenA), address(weth));
        IERC20(pair).approve(address(router), liquidity);
        
        // Only remove part of the liquidity (90%) to avoid rounding errors
        uint liquidityToRemove = liquidity * 9 / 10;
        
        // Record token balance before removal
        uint tokenBalanceBeforeRemoval = tokenA.balanceOf(address(this));
        
        // Remove liquidity with support for fee-on-transfer tokens
        uint amountETH = router.removeLiquidityETHSupportingFeeOnTransferTokens(
            address(tokenA),
            liquidityToRemove,
            0, // amountTokenMin
            0, // amountETHMin
            address(this),
            block.timestamp + 100
        );
        
        // Verify liquidity removal
        assertGt(amountETH, 0, "No ETH removed");
        
        // Check if the balances increased
        assertGt(tokenA.balanceOf(address(this)), tokenBalanceBeforeRemoval, "Token balance did not increase");
        assertGt(address(this).balance, initialETHBalance - addedETH, "ETH balance not increased after removal");
        
        // For fee-on-transfer tokens, we're particularly concerned with getting some tokens back
        // rather than a specific amount since fees might be applied
        assertGt(tokenA.balanceOf(address(this)) - tokenBalanceBeforeRemoval, 0, "No tokens received after removal");
    }

    function testRemoveLiquidityETHWithPermitSupportingFeeOnTransferTokens() public {
        // Add liquidity first with ETH and tokenA
        uint tokenAmount = 100 ether;
        uint ethAmount = 10 ether;
        
        // Add liquidity with ETH
        (,, uint liquidity) = router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0,  // amountTokenMin
            0,  // amountETHMin
            address(this),
            block.timestamp + 100
        );
        
        // Get the pair address
        address pair = factory.getPair(address(tokenA), address(weth));
        
        // Generate private key and corresponding address for signing
        uint256 privateKey = 0xABCD; // A different private key for this test
        address owner = vm.addr(privateKey);
        
        // Transfer liquidity to the owner address we'll use with permit
        IERC20(pair).transfer(owner, liquidity);
        
        // Create permit deadline
        uint deadline = block.timestamp + 100;
        
        // Generate the permit signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IUniswapV2Pair(pair).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                            owner,
                            address(router),
                            liquidity,
                            IUniswapV2Pair(pair).nonces(owner),
                            deadline
                        )
                    )
                )
            )
        );
        
        // Record initial balances
        uint initialTokenBalance = tokenA.balanceOf(owner);
        uint initialETHBalance = owner.balance;
        
        // Execute removeLiquidityETHWithPermitSupportingFeeOnTransferTokens as owner
        vm.startPrank(owner);
        uint amountETH = router.removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
            address(tokenA),
            liquidity,
            0, // amountTokenMin
            0, // amountETHMin
            owner,
            deadline,
            false, // Not approveMax
            v, r, s
        );
        vm.stopPrank();
        
        // Verify results
        assertGt(amountETH, 0, "No ETH removed");
        assertGt(tokenA.balanceOf(owner), initialTokenBalance, "Token balance did not increase");
        assertGt(owner.balance, initialETHBalance, "ETH balance did not increase");
        assertEq(IERC20(pair).balanceOf(owner), 0, "Not all LP tokens were burned");
    }
    
    // Add receive function to allow contract to receive ETH
    receive() external payable {}
}