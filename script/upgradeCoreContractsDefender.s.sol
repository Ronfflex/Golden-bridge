// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Defender, Options, ProposeUpgradeResponse} from "openzeppelin-foundry-upgrades/Defender.sol";

/**
 * @title UpgradeCoreContractsWithDefender
 * @notice Submits Defender upgrade proposals for the three Golden Bridge proxies
 * @dev Requires the following environment variables to be set before running:
 *      - GOLDTOKEN_PROXY
 *      - LOTTERIE_PROXY
 *      - TOKENBRIDGE_PROXY
 */
contract UpgradeCoreContractsWithDefender is Script {
    function run() external {
        Options memory opts;

        ProposeUpgradeResponse memory goldProposal =
            Defender.proposeUpgrade(vm.envAddress("GOLDTOKEN_PROXY"), "src/GoldToken.sol", opts);
        _logProposal("GoldToken", goldProposal);

        ProposeUpgradeResponse memory lotterieProposal =
            Defender.proposeUpgrade(vm.envAddress("LOTTERIE_PROXY"), "src/Lotterie.sol", opts);
        _logProposal("Lotterie", lotterieProposal);

        ProposeUpgradeResponse memory bridgeProposal =
            Defender.proposeUpgrade(vm.envAddress("TOKENBRIDGE_PROXY"), "src/TokenBridge.sol", opts);
        _logProposal("TokenBridge", bridgeProposal);
    }

    function _logProposal(string memory label, ProposeUpgradeResponse memory response) private pure {
        console2.log(string.concat(label, " proposal id"), response.proposalId);
        console2.log(string.concat(label, " review URL"), response.url);
    }
}
