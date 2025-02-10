// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/Lotterie.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployLotterie is Script {
    address goldToken = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B; // goldToken on sepolia
    address owner = 0xE3885EE49ffbDC52Bb9c9183aAd6E4FBe291c5A5;
    address vrfCoordinator = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B; // coordinator on sepolia

    function run() external {
        vm.startBroadcast();

        Lotterie implementation = new Lotterie(vrfCoordinator); // coordinator on sepolia

        console.log("Lotterie deployed at:", address(implementation));

        bytes memory data = abi.encodeWithSelector(
            Lotterie(implementation).initialize.selector,
            owner,
            2607541693386182620148067725411559151504172322007266401353081426276952558330,
            vrfCoordinator,
            bytes32(0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae),
            40000,
            3,
            1,
            goldToken
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        console.log("Lotterie proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
