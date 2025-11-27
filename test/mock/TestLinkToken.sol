// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title TestLinkToken
/// @notice Lightweight ERC20 used to stand in for LINK during unit tests
contract TestLinkToken is ERC20 {
    constructor() ERC20("Test Link", "TLINK") {}

    /// @notice Mints mock LINK to the requested address
    /// @param to Recipient of the minted tokens
    /// @param amount Number of tokens to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
