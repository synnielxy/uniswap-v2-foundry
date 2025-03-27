// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "forge-std/Script.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Router02.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();
        UniswapV2Factory factory = new UniswapV2Factory(msg.sender);
        UniswapV2Router02 router = new UniswapV2Router02(address(factory), address(0));
        vm.stopBroadcast();
    }
}