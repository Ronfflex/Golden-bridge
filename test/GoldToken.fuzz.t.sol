// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {IGoldToken} from "../src/interfaces/IGoldToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {GoldReference} from "./utils/GoldReference.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract GoldTokenFuzzTest is Test {
    GoldToken public goldToken;
    MockV3Aggregator public goldAggregator;
    MockV3Aggregator public ethAggregator;

    address public constant FEES_ADDRESS = address(0x1234);
    address public constant LOTTERIE_ADDRESS = address(0x5678);

    function setUp() public {
        goldAggregator = new MockV3Aggregator(8, int256(100000000000)); // 1000 USD per troy ounce
        ethAggregator = new MockV3Aggregator(8, int256(50000000000)); // 500 USD per ETH

        GoldToken implementation = new GoldToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                GoldToken.initialize.selector, address(this), address(goldAggregator), address(ethAggregator)
            )
        );
        goldToken = GoldToken(address(proxy));
        goldToken.setLotterieAddress(LOTTERIE_ADDRESS);
        goldToken.setFeesAddress(FEES_ADDRESS);
    }

    /// @notice Fuzz test minting with various ETH amounts
    function testFuzz_mint_withValidAmounts(uint96 ethAmount) public {
        vm.assume(ethAmount > 0);
        vm.assume(ethAmount < 1000 ether); // Reasonable upper bound

        vm.deal(address(this), ethAmount);

        uint256 balanceBefore = goldToken.balanceOf(address(this));
        uint256 lotterieBalanceBefore = goldToken.balanceOf(LOTTERIE_ADDRESS);
        uint256 feesBalanceBefore = goldToken.balanceOf(FEES_ADDRESS);

        goldToken.mint{value: ethAmount}();

        uint256 balanceAfter = goldToken.balanceOf(address(this));
        uint256 lotterieBalanceAfter = goldToken.balanceOf(LOTTERIE_ADDRESS);
        uint256 feesBalanceAfter = goldToken.balanceOf(FEES_ADDRESS);

        // User should receive tokens
        assertGt(balanceAfter, balanceBefore, "User balance should increase");

        // Lottery and fees should receive equal amounts (2.5% each)
        uint256 lotterieGain = lotterieBalanceAfter - lotterieBalanceBefore;
        uint256 feesGain = feesBalanceAfter - feesBalanceBefore;
        // Allow 1 wei difference due to rounding
        assertApproxEqAbs(lotterieGain, feesGain, 1, "Lottery and fees should receive equal amounts");

        // Total minted should be user + lottery + fees
        uint256 totalMinted = (balanceAfter - balanceBefore) + lotterieGain + feesGain;
        assertGt(totalMinted, 0, "Total minted should be positive");
    }

    /// @notice Fuzz test burning with various amounts
    function testFuzz_burn_withValidAmounts(uint96 ethAmount, uint88 burnAmount) public {
        vm.assume(ethAmount > 0);
        vm.assume(ethAmount < 1000 ether);

        vm.deal(address(this), ethAmount);
        goldToken.mint{value: ethAmount}();

        uint256 balance = goldToken.balanceOf(address(this));
        vm.assume(burnAmount > 0);
        vm.assume(burnAmount <= balance);

        uint256 balanceBefore = goldToken.balanceOf(address(this));
        goldToken.burn(burnAmount);
        uint256 balanceAfter = goldToken.balanceOf(address(this));

        assertEq(balanceBefore - balanceAfter, burnAmount, "Burned amount should match");
    }

    /// @notice Fuzz test transfers with various amounts
    function testFuzz_transfer_withValidAmounts(uint96 ethAmount, uint88 transferAmount, address recipient) public {
        vm.assume(ethAmount > 0);
        vm.assume(ethAmount < 1000 ether);
        vm.assume(transferAmount > 0);
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(this));
        vm.assume(recipient != LOTTERIE_ADDRESS);

        vm.deal(address(this), ethAmount);
        goldToken.mint{value: ethAmount}();

        uint256 balance = goldToken.balanceOf(address(this));
        vm.assume(transferAmount <= balance);

        uint256 senderBalanceBefore = goldToken.balanceOf(address(this));
        uint256 recipientBalanceBefore = goldToken.balanceOf(recipient);

        goldToken.transfer(recipient, transferAmount);

        uint256 senderBalanceAfter = goldToken.balanceOf(address(this));
        uint256 recipientBalanceAfter = goldToken.balanceOf(recipient);

        assertEq(senderBalanceBefore - senderBalanceAfter, transferAmount, "Sender balance decrease should match");
        assertEq(
            recipientBalanceAfter - recipientBalanceBefore, transferAmount, "Recipient balance increase should match"
        );
    }

    /// @notice Fuzz test price feed variations
    function testFuzz_mint_withVariousPrices(uint96 ethAmount, int256 goldPrice, int256 ethPrice) public {
        vm.assume(ethAmount > 0);
        vm.assume(ethAmount < 1000 ether);
        vm.assume(goldPrice > 0);
        vm.assume(goldPrice < 1e15); // Reasonable upper bound for gold price
        vm.assume(ethPrice > 0);
        vm.assume(ethPrice < 1e15); // Reasonable upper bound for ETH price

        goldAggregator.updateAnswer(goldPrice);
        ethAggregator.updateAnswer(ethPrice);

        vm.deal(address(this), ethAmount);

        try goldToken.mint{value: ethAmount}() {
            // If mint succeeds, verify user got tokens
            assertGt(goldToken.balanceOf(address(this)), 0, "User should receive tokens");
        } catch {
            // If it reverts, it should be due to zero amount calculation
            // This is acceptable for extreme price ratios
        }
    }

    /// @notice Fuzz test user tracking with multiple addresses
    function testFuzz_userTracking_multipleUsers(address[5] memory users, uint96[5] memory amounts) public {
        uint256 validUserCount = 0;

        for (uint256 i = 0; i < users.length; i++) {
            // Skip invalid addresses
            if (users[i] == address(0) || users[i] == LOTTERIE_ADDRESS || users[i] == FEES_ADDRESS) {
                continue;
            }

            // Skip duplicate addresses
            bool isDuplicate = false;
            for (uint256 j = 0; j < i; j++) {
                if (users[i] == users[j]) {
                    isDuplicate = true;
                    break;
                }
            }
            if (isDuplicate) continue;

            // Skip zero amounts
            if (amounts[i] == 0 || amounts[i] > 100 ether) continue;

            vm.deal(users[i], amounts[i]);
            vm.prank(users[i]);
            try goldToken.mint{value: amounts[i]}() {
                validUserCount++;
            } catch {
                // Skip if mint fails (e.g., amount too small)
            }
        }

        address[] memory trackedUsers = goldToken.getUsers();

        // The number of tracked users should be at least the valid user count
        assertGe(trackedUsers.length, validUserCount, "Tracked users should include all valid users");
    }

    /// @notice Fuzz test that burning below minimum removes user from tracking
    function testFuzz_userRemoval_onLowBalance(uint96 ethAmount, uint88 burnAmount) public {
        vm.assume(ethAmount > 0.01 ether);
        vm.assume(ethAmount < 1000 ether);

        vm.deal(address(this), ethAmount);
        goldToken.mint{value: ethAmount}();

        uint256 balance = goldToken.balanceOf(address(this));
        vm.assume(burnAmount > 0);
        vm.assume(burnAmount < balance);

        // Calculate how much we need to burn to go below minimum (1 ether)
        uint256 minimumGold = 1 ether;
        vm.assume(balance - burnAmount <= minimumGold);

        address[] memory usersBefore = goldToken.getUsers();
        bool wasTracked = false;
        for (uint256 i = 0; i < usersBefore.length; i++) {
            if (usersBefore[i] == address(this)) {
                wasTracked = true;
                break;
            }
        }

        goldToken.burn(burnAmount);

        if (goldToken.balanceOf(address(this)) <= minimumGold && wasTracked) {
            address[] memory usersAfter = goldToken.getUsers();
            bool stillTracked = false;
            for (uint256 i = 0; i < usersAfter.length; i++) {
                if (usersAfter[i] == address(this)) {
                    stillTracked = true;
                    break;
                }
            }
            assertFalse(stillTracked, "User should be removed from tracking when balance <= minimum");
        }
    }

    /// @notice Fuzz test that contract never mints more than expected
    function testFuzz_noExcessMinting(uint96 ethAmount) public {
        vm.assume(ethAmount > 0);
        vm.assume(ethAmount < 1000 ether);
        vm.assume(ethAmount >= 0.001 ether);

        int256 goldPriceInEth = goldToken.getGoldPriceInEth();
        vm.assume(goldPriceInEth > 0);

        uint256 goldPriceScaled = uint256(goldPriceInEth) * 10 ** 10;
        uint256 minDeposit = (goldPriceScaled + 10 ** 18 - 1) / 10 ** 18;
        vm.assume(ethAmount >= minDeposit);

        vm.deal(address(this), ethAmount);

        uint256 userBefore = goldToken.balanceOf(address(this));
        uint256 lotterieBefore = goldToken.balanceOf(LOTTERIE_ADDRESS);
        uint256 feesBefore = goldToken.balanceOf(FEES_ADDRESS);

        goldToken.mint{value: ethAmount}();
        uint256 userAfter = goldToken.balanceOf(address(this));
        uint256 lotterieAfter = goldToken.balanceOf(LOTTERIE_ADDRESS);
        uint256 feesAfter = goldToken.balanceOf(FEES_ADDRESS);

        assertGe(userAfter, userBefore, "User balance should not decrease");
        assertGe(lotterieAfter, lotterieBefore, "Lotterie balance should not decrease");
        assertGe(feesAfter, feesBefore, "Fees balance should not decrease");

        uint256 userDelta = userAfter - userBefore;
        uint256 lotterieDelta = lotterieAfter - lotterieBefore;
        uint256 feesDelta = feesAfter - feesBefore;

        uint256 totalMinted = userDelta + lotterieDelta + feesDelta;
        assertGt(totalMinted, 0, "Total minted should be positive");

        // Calculate expected maximum minted amount based on current prices
        uint256 maxExpected = Math.mulDiv(ethAmount, 10 ** 18, goldPriceScaled);

        // Total minted should not exceed the raw calculation (before fees are subtracted)
        assertLe(totalMinted, maxExpected, "Should not mint more than calculated amount");
    }

    /// @notice Fuzz test ensuring user registry remains unique and timestamps stay populated
    function testFuzz_userRegistryIntegrity(address[5] memory users, uint96[5] memory amounts) public {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == address(0) || users[i] == LOTTERIE_ADDRESS || users[i] == FEES_ADDRESS) {
                continue;
            }

            // Ensure deterministic order by skipping duplicates that appear earlier in the array
            bool duplicate = false;
            for (uint256 j = 0; j < i; j++) {
                if (users[i] == users[j]) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;

            uint256 amount = bound(amounts[i], 0.02 ether, 200 ether);
            vm.deal(users[i], amount);
            vm.prank(users[i]);
            goldToken.mint{value: amount}();
        }

        (address[] memory trackedUsers, uint256[] memory timestamps) = goldToken.getTimestamps();

        for (uint256 i = 0; i < trackedUsers.length; i++) {
            address user = trackedUsers[i];
            assertEq(user != address(0), true, "Tracked user cannot be zero");
            assertGt(timestamps[i], 0, "Timestamp should be initialized");
            assertGt(goldToken.balanceOf(user), 0, "Tracked user must hold GLD");

            for (uint256 j = i + 1; j < trackedUsers.length; j++) {
                assertTrue(trackedUsers[j] != user, "User list must not contain duplicates");
            }
        }
    }

    /// @notice Fuzz test fee accounting remains consistent with 5% fee split
    function testFuzz_mint_feeAccounting(uint96 ethAmount) public {
        vm.assume(ethAmount > 0.05 ether);
        vm.assume(ethAmount < 200 ether);

        int256 goldPriceInEth = goldToken.getGoldPriceInEth();
        vm.assume(goldPriceInEth > 0);

        uint256 goldPriceScaled = uint256(goldPriceInEth) * 10 ** 10;
        uint256 rawGoldAmount = Math.mulDiv(ethAmount, 10 ** 18, goldPriceScaled);
        vm.assume(rawGoldAmount > 0);

        uint256 expectedFee = rawGoldAmount * 5 / 100;
        vm.assume(expectedFee > 0);
        uint256 expectedUserAmount = rawGoldAmount - expectedFee;
        uint256 expectedLotterie = expectedFee / 2;
        uint256 expectedFeesAddress = expectedFee - expectedLotterie;

        vm.deal(address(this), ethAmount);
        uint256 userBefore = goldToken.balanceOf(address(this));
        uint256 lotterieBefore = goldToken.balanceOf(LOTTERIE_ADDRESS);
        uint256 feesBefore = goldToken.balanceOf(FEES_ADDRESS);

        goldToken.mint{value: ethAmount}();

        uint256 userDelta = goldToken.balanceOf(address(this)) - userBefore;
        uint256 lotterieDelta = goldToken.balanceOf(LOTTERIE_ADDRESS) - lotterieBefore;
        uint256 feesDelta = goldToken.balanceOf(FEES_ADDRESS) - feesBefore;

        assertApproxEqAbs(userDelta, expectedUserAmount, 1, "User mint amount mismatch");
        assertApproxEqAbs(lotterieDelta, expectedLotterie, 1, "Lotterie fee share mismatch");
        assertApproxEqAbs(feesDelta, expectedFeesAddress, 1, "Fees address share mismatch");
    }

    /// @notice Fuzz test ensures minting respects the minimum deposit implied by price feeds
    function testFuzz_mint_respectsMinimumDeposit(uint96 ethAmount) public {
        vm.assume(ethAmount > 0);
        vm.assume(ethAmount < 10 ether);

        vm.deal(address(this), ethAmount);

        int256 goldPriceInEth = goldToken.getGoldPriceInEth();
        vm.assume(goldPriceInEth > 0);
        uint256 goldPriceScaled = uint256(goldPriceInEth) * 10 ** 10;
        uint256 minDeposit = (goldPriceScaled + 10 ** 18 - 1) / 10 ** 18;

        if (ethAmount < minDeposit) {
            vm.expectRevert(IGoldToken.AmountMustBeGreaterThanZero.selector);
            goldToken.mint{value: ethAmount}();
        } else {
            goldToken.mint{value: ethAmount}();
        }
    }

    /// @notice Fuzz test ensures paused state blocks minting
    function testFuzz_pauseBlocksMint(uint96 ethAmount) public {
        vm.assume(ethAmount > 0.05 ether);
        vm.assume(ethAmount < 100 ether);

        vm.deal(address(this), ethAmount);
        goldToken.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        goldToken.mint{value: ethAmount}();

        goldToken.unpause();
    }

    /// @notice Differential fuzz test comparing on-chain price math with reference implementation
    function testFuzz_goldPriceMatchesReference(uint64 goldUsdRaw, uint64 ethUsdRaw) public {
        uint256 goldBounded = bound(uint256(goldUsdRaw), 100 * 1e8, 10_000 * 1e8);
        uint256 ethBounded = bound(uint256(ethUsdRaw), 100 * 1e8, 10_000 * 1e8);

        int256 goldUsdPerTroyOunce = int256(goldBounded);
        int256 ethUsd = int256(ethBounded);

        goldAggregator.updateAnswer(goldUsdPerTroyOunce);
        ethAggregator.updateAnswer(ethUsd);

        int256 expected = GoldReference.calcGoldPriceInEth(goldUsdPerTroyOunce, ethUsd);
        assertEq(goldToken.getGoldPriceInEth(), expected, "price mismatch with reference implementation");
    }

    receive() external payable {}
}
