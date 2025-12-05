// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Lotterie} from "../src/Lotterie.sol";
import {ILotterie} from "../src/interfaces/ILotterie.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract LotterieFuzzTest is Test {
    GoldToken public goldToken;
    MockV3Aggregator public mockGold;
    MockV3Aggregator public mockEth;
    Lotterie public lotterie;
    VRFCoordinatorV2_5Mock public vrfCoordinator;

    uint256 public vrfSubscriptionId;

    function setUp() public {
        vm.warp(block.timestamp + 2 days);

        mockGold = new MockV3Aggregator(8, int256(100000000000));
        mockEth = new MockV3Aggregator(8, int256(50000000000));

        GoldToken implementation1 = new GoldToken();
        ERC1967Proxy proxy1 = new ERC1967Proxy(
            address(implementation1),
            abi.encodeWithSelector(GoldToken.initialize.selector, address(this), address(mockGold), address(mockEth))
        );
        goldToken = GoldToken(address(proxy1));

        vrfCoordinator = new VRFCoordinatorV2_5Mock(100000000000000000, 1000000000, 6944258275756201);
        vrfSubscriptionId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(vrfSubscriptionId, 1000000000000000000000000);

        Lotterie implementation2 = new Lotterie(address(vrfCoordinator));
        ERC1967Proxy proxy2 = new ERC1967Proxy(
            address(implementation2),
            abi.encodeWithSelector(
                Lotterie.initialize.selector,
                address(this),
                vrfSubscriptionId,
                address(vrfCoordinator),
                bytes32(0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae),
                40_000,
                3,
                1,
                86_400, // One day
                address(goldToken)
            )
        );
        lotterie = Lotterie(address(proxy2));

        vrfCoordinator.addConsumer(vrfSubscriptionId, address(lotterie));
        goldToken.setLotterieAddress(address(lotterie));
    }

    /// @notice Fuzz test VRF configuration parameters
    function testFuzz_vrfConfiguration(uint32 gasLimit, uint16 confirmations, uint32 numWords) public {
        vm.assume(gasLimit > 10000);
        vm.assume(gasLimit < 10000000);
        vm.assume(confirmations > 0);
        vm.assume(confirmations < 100);
        vm.assume(numWords > 0);
        vm.assume(numWords < 10);

        lotterie.setCallbackGasLimit(gasLimit);
        lotterie.setRequestConfirmations(confirmations);
        lotterie.setNumWords(numWords);

        assertEq(lotterie.getCallbackGasLimit(), gasLimit, "Gas limit should match");
        assertEq(lotterie.getRequestConfirmations(), confirmations, "Confirmations should match");
        assertEq(lotterie.getNumWords(), numWords, "Num words should match");
    }

    /// @notice Fuzz test lottery draw with multiple users
    function testFuzz_randomDraw_withMultipleUsers(uint8 userCount, uint96 mintAmount) public {
        vm.assume(userCount > 0);
        vm.assume(userCount <= 20);
        vm.assume(mintAmount > 0.01 ether);
        vm.assume(mintAmount < 10 ether);

        // Create users and mint tokens
        for (uint256 i = 0; i < userCount; i++) {
            // casting to uint160 is safe because the literal offsets are < 2**160
            // forge-lint: disable-next-line(unsafe-typecast)
            address user = address(uint160(0x1000 + i));
            vm.deal(user, mintAmount);
            vm.prank(user);
            goldToken.mint{value: mintAmount}();
        }

        uint256 lotterieBalance = goldToken.balanceOf(address(lotterie));
        vm.assume(lotterieBalance > 0);

        vm.warp(block.timestamp + 1 days);

        uint256 requestId = lotterie.randomDraw(false);
        assertGt(requestId, 0, "Request ID should be positive");

        // Fulfill the randomness
        vrfCoordinator.fulfillRandomWords(requestId, address(lotterie));

        address winner = lotterie.getResults(requestId);
        assertNotEq(winner, address(0), "Winner should be set");

        uint256 gains = lotterie.getGains(winner);
        assertEq(gains, lotterieBalance, "Winner gains should equal lottery balance");
    }

    /// @notice Fuzz test claim functionality with various scenarios
    function testFuzz_claim_withDifferentAmounts(uint96 mintAmount1, uint96 mintAmount2) public {
        vm.assume(mintAmount1 > 0.01 ether);
        vm.assume(mintAmount1 < 10 ether);
        vm.assume(mintAmount2 > 0.01 ether);
        vm.assume(mintAmount2 < 10 ether);

        address user1 = address(0x1001);
        address user2 = address(0x1002);

        vm.deal(user1, mintAmount1);
        vm.prank(user1);
        goldToken.mint{value: mintAmount1}();

        vm.deal(user2, mintAmount2);
        vm.prank(user2);
        goldToken.mint{value: mintAmount2}();

        vm.warp(block.timestamp + 1 days);

        uint256 requestId = lotterie.randomDraw(false);
        vrfCoordinator.fulfillRandomWords(requestId, address(lotterie));

        address winner = lotterie.getResults(requestId);
        uint256 expectedGains = lotterie.getGains(winner);
        uint256 balanceBefore = goldToken.balanceOf(winner);

        vm.prank(winner);
        lotterie.claim();

        uint256 balanceAfter = goldToken.balanceOf(winner);
        assertEq(balanceAfter - balanceBefore, expectedGains, "Balance increase should match gains");
        assertEq(lotterie.getGains(winner), 0, "Gains should be reset after claim");
    }

    /// @notice Fuzz test time constraints between draws
    function testFuzz_randomDraw_timeConstraints(uint32 timeElapsed, uint32 cooldown) public {
        vm.assume(cooldown > 1 hours);
        vm.assume(cooldown < 365 days);
        vm.assume(timeElapsed < cooldown * 2);

        lotterie.setRandomDrawCooldown(cooldown);

        vm.deal(address(this), 1 ether);
        goldToken.mint{value: 1 ether}();

        vm.warp(block.timestamp + cooldown);
        lotterie.randomDraw(false);

        vm.warp(block.timestamp + timeElapsed);

        if (timeElapsed < cooldown) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ILotterie.DrawCooldownNotExpired.selector, block.timestamp - timeElapsed, cooldown, block.timestamp
                )
            );
            lotterie.randomDraw(false);
        } else {
            uint256 requestId = lotterie.randomDraw(false);
            assertGt(requestId, 0, "Should succeed after cooldown");
        }
    }

    /// @notice Fuzz test VRF subscription ID changes
    function testFuzz_setVrfSubscriptionId(uint256 newSubscriptionId) public {
        vm.assume(newSubscriptionId > 0);
        vm.assume(newSubscriptionId < type(uint128).max);

        lotterie.setVrfSubscriptionId(newSubscriptionId);
        assertEq(lotterie.getVrfSubscriptionId(), newSubscriptionId, "Subscription ID should update");
    }

    /// @notice Fuzz test multiple consecutive draws
    function testFuzz_multipleDraws(uint8 drawCount) public {
        vm.assume(drawCount > 0);
        vm.assume(drawCount <= 10);

        vm.deal(address(this), 100 ether);
        goldToken.mint{value: 10 ether}();

        uint256 currentTime = block.timestamp;
        for (uint256 i = 0; i < drawCount; i++) {
            currentTime += 1 days + 1;
            vm.warp(currentTime);
            uint256 requestId = lotterie.randomDraw(false);
            assertGt(requestId, 0, "Request ID should be positive");

            vrfCoordinator.fulfillRandomWords(requestId, address(lotterie));
            address winner = lotterie.getResults(requestId);

            if (goldToken.balanceOf(address(lotterie)) > 0) {
                assertNotEq(winner, address(0), "Winner should be set");
            }
        }
    }

    /// @notice Fuzz test that lottery correctly handles edge cases in user selection
    function testFuzz_userSelection_withVaryingSizes(uint8 userCount) public {
        vm.assume(userCount > 0);
        vm.assume(userCount <= 50);

        // Create users with varying amounts
        for (uint256 i = 0; i < userCount; i++) {
            // casting to uint160 is safe because the literal offsets are < 2**160
            // forge-lint: disable-next-line(unsafe-typecast)
            address user = address(uint160(0x2000 + i));
            uint256 amount = 0.01 ether + (i * 0.001 ether);
            vm.deal(user, amount);
            vm.prank(user);
            goldToken.mint{value: amount}();
        }

        vm.warp(block.timestamp + 1 days);
        uint256 requestId = lotterie.randomDraw(false);
        vrfCoordinator.fulfillRandomWords(requestId, address(lotterie));

        address winner = lotterie.getResults(requestId);

        // Winner must be one of the users
        bool isValidWinner = false;
        for (uint256 i = 0; i < userCount; i++) {
            // casting to uint160 is safe because the literal offsets are < 2**160
            // forge-lint: disable-next-line(unsafe-typecast)
            if (winner == address(uint160(0x2000 + i))) {
                isValidWinner = true;
                break;
            }
        }
        assertTrue(isValidWinner, "Winner must be from the user pool");
    }

    /// @notice Fuzz test that gains snapshot matches Lotterie GLD balance
    function testFuzz_gainsMatchesBalance(uint96 mintAmount) public {
        mintAmount = uint96(bound(mintAmount, 0.05 ether, 5 ether));

        address user1 = address(0x4001);
        address user2 = address(0x4002);

        vm.deal(user1, mintAmount);
        vm.prank(user1);
        goldToken.mint{value: mintAmount}();

        vm.deal(user2, mintAmount);
        vm.prank(user2);
        goldToken.mint{value: mintAmount}();

        vm.warp(block.timestamp + 1 days);
        uint256 balanceBefore = goldToken.balanceOf(address(lotterie));
        vm.assume(balanceBefore > 0);

        uint256 requestId = lotterie.randomDraw(false);
        vrfCoordinator.fulfillRandomWords(requestId, address(lotterie));

        address winner = lotterie.getResults(requestId);
        uint256 gains = lotterie.getGains(winner);
        assertEq(gains, balanceBefore, "Gains should equal Lotterie balance snapshot");
    }

    /// @notice Fuzz test switching the GoldToken source updates participant pool
    function testFuzz_setGoldTokenSwitchesSource(uint96 mintAmount1, uint96 mintAmount2) public {
        mintAmount1 = uint96(bound(mintAmount1, 0.05 ether, 5 ether));
        mintAmount2 = uint96(bound(mintAmount2, 0.05 ether, 5 ether));

        GoldToken newImplementation = new GoldToken();
        ERC1967Proxy newProxy = new ERC1967Proxy(
            address(newImplementation),
            abi.encodeWithSelector(GoldToken.initialize.selector, address(this), address(mockGold), address(mockEth))
        );
        GoldToken newGoldToken = GoldToken(address(newProxy));
        newGoldToken.setLotterieAddress(address(lotterie));

        lotterie.setGoldToken(address(newGoldToken));

        address userA = address(0x5001);
        address userB = address(0x5002);

        vm.deal(userA, mintAmount1);
        vm.prank(userA);
        newGoldToken.mint{value: mintAmount1}();

        vm.deal(userB, mintAmount2);
        vm.prank(userB);
        newGoldToken.mint{value: mintAmount2}();

        vm.warp(block.timestamp + 1 days);
        uint256 requestId = lotterie.randomDraw(false);
        vrfCoordinator.fulfillRandomWords(requestId, address(lotterie));

        address winner = lotterie.getResults(requestId);
        assertTrue(winner == userA || winner == userB, "Winner must come from new GoldToken users");
        assertEq(lotterie.getGoldToken(), address(newGoldToken), "GoldToken address should update");
    }

    /// @notice Documents that draws without users keep winner unset
    function test_randomDraw_withoutUsersLeavesWinnerUnset() public {
        vm.warp(block.timestamp + 1 days);
        uint256 requestId = lotterie.randomDraw(false);

        vrfCoordinator.fulfillRandomWords(requestId, address(lotterie));

        assertEq(lotterie.getResults(requestId), address(0), "Winner should remain unset without participants");
    }

    receive() external payable {}
}
