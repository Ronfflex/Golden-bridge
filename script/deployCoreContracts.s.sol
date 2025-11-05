// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {Lotterie} from "../src/Lotterie.sol";
import {TokenBridge} from "../src/TokenBridge.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployCoreContracts
 * @notice Deployment script for the Golden Bridge system
 * @dev This script needs to be run twice - once on each chain (Sepolia and BSC Testnet)
 *      After deployment, the bridge contracts need to be configured to trust each other
 *
 * Deploy steps:
 * 0. Environment variables:
 *    Make sure you have completed the required fields in the .env file.
 *
 * 1. Deploy on Sepolia:
 *    forge script script/deployCoreContracts.s.sol:DeployCoreContracts --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify
 *
 * 2. Deploy on BSC Testnet:
 *    forge script script/deployCoreContracts.s.sol:DeployCoreContracts --rpc-url $BNB_CHAIN_TESTNET_RPC_URL --broadcast --verify --gas-price 3000000000
 *
 * 3. After deployment, call these functions on both bridge contracts:
 *    - setWhitelistedSender(otherBridgeAddress, true)
 *    - On Sepolia: setWhitelistedChain(BSC_CHAIN_SELECTOR, true, defaultExtraArgs)
 *    - On BSC: setWhitelistedChain(SEPOLIA_CHAIN_SELECTOR, true, defaultExtraArgs)
 */
contract DeployCoreContracts is Script {
    // Network specific configurations
    struct NetworkConfig {
        address router; // CCIP Router
        address link; // LINK Token
        uint256 vrfSubscriptionId; // VRF Subscription ID
        uint64 chainSelector; // This chain's selector
        uint64 destSelector; // Destination chain's selector
        address goldUsdFeed; // Gold/USD price feed
        address ethUsdFeed; // ETH/USD or BNB/USD price feed
        address vrfCoordinator; // VRF Coordinator
        bytes32 keyHash; // VRF key hash
    }

    // Sepolia network configuration
    NetworkConfig sepoliaConfig = NetworkConfig({
        router: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
        link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
        vrfSubscriptionId: uint256(vm.envUint("ETHEREUM_SEPOLIA_VRF_SUBSCRIPTION_ID")),
        chainSelector: 16015286601757825753, // Sepolia chain selector
        destSelector: 13264668187771770619, // BSC Testnet selector
        goldUsdFeed: 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea,
        ethUsdFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
        vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
        keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
    });

    // BSC Testnet network configuration
    NetworkConfig bscTestnetConfig = NetworkConfig({
        router: 0x9527E2D01a3064eF6B50c1DA1C0cc523803BcDf3,
        link: 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06,
        vrfSubscriptionId: uint256(vm.envUint("BSC_TESTNET_VRF_SUBSCRIPTION_ID")),
        chainSelector: 13264668187771770619, // BSC Testnet chain selector
        destSelector: 16015286601757825753, // Sepolia selector
        goldUsdFeed: 0x569B6c1C194ff744F344B862aD5039B106271601, // Replace with actual BSC feed
        ethUsdFeed: 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526, // BNB/USD feed
        vrfCoordinator: 0xDA3b641D438362C440Ac5458c57e00a712b66700,
        keyHash: 0x8596b430971ac45bdf6088665b9ad8e8630c9d5049ab54b14dff711bee7c0e26
    });

    // Chainlink VRF parameters (same for both networks)
    uint32 constant CALLBACK_GAS_LIMIT = 40000;
    uint16 constant REQUEST_CONFIRMATIONS = 3;
    uint32 constant NUM_WORDS = 1;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Determine which network we're deploying to based on the chain ID
        uint256 chainId = block.chainid;
        NetworkConfig memory config;

        if (chainId == 11155111) {
            // Sepolia
            config = sepoliaConfig;
            console2.log("Deploying to Sepolia. Chain ID:", chainId);
        } else if (chainId == 97) {
            // BSC Testnet
            config = bscTestnetConfig;
            console2.log("Deploying to BSC Testnet. Chain ID:", chainId);
        } else {
            revert("Unsupported network");
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation contracts
        GoldToken goldTokenImpl = new GoldToken();
        Lotterie lotterieImpl = new Lotterie(config.vrfCoordinator);
        TokenBridge bridgeImpl = new TokenBridge(config.router);

        // Deploy proxies
        bytes memory goldTokenData =
            abi.encodeWithSelector(GoldToken.initialize.selector, deployer, config.goldUsdFeed, config.ethUsdFeed);
        ERC1967Proxy goldTokenProxy = new ERC1967Proxy(address(goldTokenImpl), goldTokenData);
        GoldToken goldToken = GoldToken(address(goldTokenProxy));

        bytes memory lotterieData = abi.encodeWithSelector(
            Lotterie.initialize.selector,
            deployer,
            config.vrfSubscriptionId,
            config.vrfCoordinator,
            config.keyHash,
            CALLBACK_GAS_LIMIT,
            REQUEST_CONFIRMATIONS,
            NUM_WORDS,
            address(goldToken)
        );
        ERC1967Proxy lotterieProxy = new ERC1967Proxy(address(lotterieImpl), lotterieData);
        Lotterie lotterie = Lotterie(address(lotterieProxy));

        bytes memory bridgeData = abi.encodeWithSelector(
            TokenBridge.initialize.selector,
            deployer,
            config.link,
            address(goldToken),
            config.destSelector // Configure with the destination chain's selector
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(bridgeImpl), bridgeData);
        TokenBridge bridge = TokenBridge(payable(address(bridgeProxy)));

        // Set up contract relationships
        goldToken.setLotterieAddress(address(lotterie));
        goldToken.setFeesAddress(address(lotterie));

        // Output deployed addresses
        //console2.log("\nDeployment on chain", chainId);
        console2.log("===========================================");
        console2.log("GoldToken implementation:", address(goldTokenImpl));
        console2.log("GoldToken proxy:", address(goldToken));
        console2.log("Lotterie implementation:", address(lotterieImpl));
        console2.log("Lotterie proxy:", address(lotterie));
        console2.log("TokenBridge implementation:", address(bridgeImpl));
        console2.log("TokenBridge proxy:", address(bridge));
        console2.log("\nNext steps:");
        console2.log("1. Deploy on the other chain if not already done");
        console2.log("2. Call setWhitelistedSender() on both bridges");
        console2.log("3. Call setWhitelistedChain() on both bridges");

        vm.stopBroadcast();
    }
}
