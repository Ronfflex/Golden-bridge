// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IGoldToken} from "../../src/interfaces/IGoldToken.sol";

/// @title ContractThatRejectsEth
/// @notice Test helper that reverts on native ETH transfers to simulate failing beneficiaries
contract ContractThatRejectsEth {
    /// @notice Always reverts to force upstream logic down the failure path
    receive() external payable {
        revert("I reject ETH");
    }

    /// @notice Calls `GoldToken.claimEth` while this contract is the owner to exercise failure cases
    /// @param goldToken GoldToken instance whose ETH withdrawal should be attempted
    function claimGoldTokenEth(IGoldToken goldToken) external {
        goldToken.claimEth();
    }
}
