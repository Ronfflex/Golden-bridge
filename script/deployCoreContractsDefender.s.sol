// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {Lotterie} from "../src/Lotterie.sol";
import {ILotterie} from "../src/interfaces/ILotterie.sol";
import {TokenBridge} from "../src/TokenBridge.sol";
import {ApprovalProcessResponse, Defender} from "openzeppelin-foundry-upgrades/Defender.sol";
import {Options, Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * @title DeployCoreContractsWithDefender
 * @notice Deploys the Golden Bridge proxies through OpenZeppelin Defender Deploy
 * @dev Mirrors the logic from DeployCoreContracts but routes deployments through
 *      openzeppelin-foundry-upgrades so relayers/Safe approvals can manage ownership.
 */
contract DeployCoreContractsWithDefender is Script {
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

    error UnsupportedNetwork(uint256 chainId);
    error MissingApprovalProcess();

    // Sepolia network configuration
    NetworkConfig internal sepoliaConfig = NetworkConfig({
        router: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
        link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
        vrfSubscriptionId: uint256(vm.envUint("ETHEREUM_SEPOLIA_VRF_SUBSCRIPTION_ID")),
        chainSelector: 16015286601757825753,
        destSelector: 13264668187771770619,
        goldUsdFeed: 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea,
        ethUsdFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
        vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
        keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
    });

    // BSC Testnet configuration
    NetworkConfig internal bscConfig = NetworkConfig({
        router: 0x9527E2D01a3064eF6B50c1DA1C0cc523803BcDf3,
        link: 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06,
        vrfSubscriptionId: uint256(vm.envUint("BSC_TESTNET_VRF_SUBSCRIPTION_ID")),
        chainSelector: 13264668187771770619,
        destSelector: 16015286601757825753,
        goldUsdFeed: 0x569B6c1C194ff744F344B862aD5039B106271601,
        ethUsdFeed: 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526,
        vrfCoordinator: 0xDA3b641D438362C440Ac5458c57e00a712b66700,
        keyHash: 0x8596b430971ac45bdf6088665b9ad8e8630c9d5049ab54b14dff711bee7c0e26
    });

    uint32 constant CALLBACK_GAS_LIMIT = 40000;
    uint16 constant REQUEST_CONFIRMATIONS = 3;
    uint32 constant NUM_WORDS = 1;
    bool constant VRF_NATIVE_PAYMENT = false;
    uint32 constant RANDOM_DRAW_COOLDOWN = 1 days;

    function run() external {
        NetworkConfig memory config = _currentNetwork();
        address owner = _resolveOwner();

        Options memory sharedOpts;
        sharedOpts.defender.useDefenderDeploy = true;

        address goldTokenProxy = Upgrades.deployUUPSProxy(
            "src/GoldToken.sol",
            abi.encodeCall(GoldToken.initialize, (owner, config.goldUsdFeed, config.ethUsdFeed)),
            sharedOpts
        );

        Options memory lotterieOpts = sharedOpts;
        lotterieOpts.constructorData = abi.encode(config.vrfCoordinator);
        address lotterieProxy = Upgrades.deployUUPSProxy(
            "src/Lotterie.sol",
            abi.encodeCall(
                Lotterie.initialize,
                (ILotterie.LotterieConfig({
                        owner: owner,
                        vrfSubscriptionId: config.vrfSubscriptionId,
                        vrfCoordinator: config.vrfCoordinator,
                        vrfNativePayment: VRF_NATIVE_PAYMENT,
                        keyHash: config.keyHash,
                        callbackGasLimit: CALLBACK_GAS_LIMIT,
                        requestConfirmations: REQUEST_CONFIRMATIONS,
                        numWords: NUM_WORDS,
                        randomDrawCooldown: RANDOM_DRAW_COOLDOWN,
                        goldToken: goldTokenProxy
                    }))
            ),
            lotterieOpts
        );

        Options memory bridgeOpts = sharedOpts;
        bridgeOpts.constructorData = abi.encode(config.router);
        address bridgeProxy = Upgrades.deployUUPSProxy(
            "src/TokenBridge.sol",
            abi.encodeCall(TokenBridge.initialize, (owner, config.link, goldTokenProxy, config.destSelector)),
            bridgeOpts
        );

        console2.log("===========================================");
        console2.log(" Defender Deploy summary");
        console2.log(" - Owner (Safe)        :", owner);
        console2.log(" - GoldToken proxy     :", goldTokenProxy);
        console2.log(" - Lotterie proxy      :", lotterieProxy);
        console2.log(" - TokenBridge proxy   :", bridgeProxy);
        console2.log("===========================================");
        console2.log("Next steps: use the OWNER_ROLE account (Safe) to");
        console2.log("  * call setLotterieAddress() and setFeesAddress() on GoldToken");
        console2.log("  * whitelist chains/senders on TokenBridge as outlined in DEPLOYMENT_GUIDE.md");
    }

    function _currentNetwork() private view returns (NetworkConfig memory) {
        if (block.chainid == 11155111) {
            return sepoliaConfig;
        }
        if (block.chainid == 97) {
            return bscConfig;
        }
        revert UnsupportedNetwork(block.chainid);
    }

    function _resolveOwner() private returns (address) {
        ApprovalProcessResponse memory approval = Defender.getUpgradeApprovalProcess();
        if (approval.via == address(0)) revert MissingApprovalProcess();
        return approval.via;
    }
}
