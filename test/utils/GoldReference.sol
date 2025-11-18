// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title GoldReference
 * @notice Helper utilities used by tests to validate GoldToken math against a reference implementation.
 */
library GoldReference {
    uint256 internal constant FEE_PERCENT = 5;

    /// @notice Mirror of GoldToken.getGoldPriceInEth logic for testing
    function calcGoldPriceInEth(int256 goldUsdPerTroyOunce, int256 ethUsd) internal pure returns (int256) {
        require(goldUsdPerTroyOunce > 0, "invalid feeds");
        require(ethUsd > 0, "invalid feeds");

        int256 goldUsdPerGram = (goldUsdPerTroyOunce * 10_000_000) / 311_034_768;
        return (goldUsdPerGram * 1e8) / ethUsd;
    }

    /// @notice Reference calculation replicating GoldToken.mint outputs
    function calcMintBreakdown(uint256 ethAmount, int256 goldUsdPerTroyOunce, int256 ethUsd)
        internal
        pure
        returns (uint256 userAmount, uint256 lotterieAmount, uint256 feesAmount)
    {
        require(ethAmount > 0, "invalid eth");
        int256 price = calcGoldPriceInEth(goldUsdPerTroyOunce, ethUsd);
        require(price > 0, "invalid price");

        // casting to uint256 is safe because price > 0 is enforced above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 goldPriceScaled = uint256(price) * 1e10;
        uint256 grossGold = ethAmount * 1e18 / goldPriceScaled;
        require(grossGold > 0, "zero mint");

        uint256 fee = grossGold * FEE_PERCENT / 100;
        userAmount = grossGold - fee;
        lotterieAmount = fee / 2;
        feesAmount = fee - lotterieAmount;
    }
}
