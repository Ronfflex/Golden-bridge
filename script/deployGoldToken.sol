// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/GoldToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployGoldToken is Script {
    function run() external {
        vm.startBroadcast();

        GoldToken implementation = new GoldToken();

        console.log("GoldToken deployed at:", address(implementation));

        bytes memory data = abi.encodeWithSelector(GoldToken(implementation).initialize.selector, msg.sender);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        console.log("GoldToken proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
