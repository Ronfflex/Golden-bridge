// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployGoldToken is Script {
    function run() external {
        vm.startBroadcast();

        GoldToken implementation = new GoldToken();

        console2.log("GoldToken deployed at:", address(implementation));

        bytes memory data = abi.encodeWithSelector(GoldToken(implementation).initialize.selector, msg.sender);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        console2.log("GoldToken proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
