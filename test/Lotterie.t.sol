// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {Lotterie} from "../src/Lotterie.sol";
import {ILotterie} from "../src/interfaces/ILotterie.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract LotterieTest is Test {
    address[] public signers;

    GoldToken public goldToken;
    MockV3Aggregator public mockGold;
    MockV3Aggregator public mockEth;

    Lotterie public lotterie;
    VRFCoordinatorV2_5Mock public vrfCoordinator;

    event LotterieInitialized(
        address indexed owner,
        address indexed vrfCoordinator,
        address indexed goldToken,
        uint256 vrfSubscriptionId,
        bool vrfNativePayment,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords,
        uint256 randomDrawCooldown
    );
    event VrfSubscriptionUpdated(uint256 indexed previousSubscriptionId, uint256 indexed newSubscriptionId);
    event VrfCoordinatorUpdated(address indexed previousCoordinator, address indexed newCoordinator);
    event KeyHashUpdated(bytes32 indexed previousKeyHash, bytes32 indexed newKeyHash);
    event CallbackGasLimitUpdated(uint32 indexed previousGasLimit, uint32 indexed newGasLimit);
    event RequestConfirmationsUpdated(uint16 indexed previousConfirmations, uint16 indexed newConfirmations);
    event NumWordsUpdated(uint32 indexed previousNumWords, uint32 indexed newNumWords);
    event GoldTokenUpdated(address indexed previousGoldToken, address indexed newGoldToken);
    event RandomDrawCooldownUpdated(uint256 indexed previousCooldown, uint256 indexed newCooldown);
    event VrfNativePaymentUpdated(bool indexed previousNativePayment, bool indexed newNativePayment);
    event GainClaimed(address indexed account, uint256 amount);

    function setUp() public {
        vm.deal(address(this), 100 ether);
        // Advance time by 2 days to avoid underflow issues with last random draw time (set during initialization to block.timestamp - 1 days)
        vm.warp(block.timestamp + 2 days);

        signers = [address(0x1), address(0x2), address(0x3)];

        mockGold = new MockV3Aggregator(8, int256(100000000000)); // 100.00 USD
        mockEth = new MockV3Aggregator(8, int256(50000000000)); // 50.00 USD

        GoldToken implementation1 = new GoldToken();
        ERC1967Proxy proxy1 = new ERC1967Proxy(
            address(implementation1),
            abi.encodeWithSelector(GoldToken.initialize.selector, address(this), address(mockGold), address(mockEth))
        );
        goldToken = GoldToken(address(proxy1));

        vrfCoordinator = new VRFCoordinatorV2_5Mock(100000000000000000, 1000000000, 6944258275756201);
        uint256 subscription = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subscription, 100000000000000000000);

        Lotterie implementation2 = new Lotterie(address(vrfCoordinator));
        ERC1967Proxy proxy2 = new ERC1967Proxy(
            address(implementation2),
            abi.encodeWithSelector(
                Lotterie.initialize.selector,
                address(this),
                subscription,
                address(vrfCoordinator),
                false,
                bytes32(0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae),
                100000,
                3,
                1,
                86400,
                address(goldToken)
            )
        );
        lotterie = Lotterie(address(proxy2));

        vrfCoordinator.addConsumer(subscription, address(lotterie));

        goldToken.setLotterieAddress(address(lotterie));
        goldToken.mint{value: 10000}();
        bool transferToSigner0 = goldToken.transfer(signers[0], 100);
        bool transferToSigner1 = goldToken.transfer(signers[1], 100);
        assertTrue(transferToSigner0, "transfer to signer 0 should succeed");
        assertTrue(transferToSigner1, "transfer to signer 1 should succeed");
    }

    function test_addOwner() public {
        lotterie.addOwner(signers[0]);
        bool isOwner = lotterie.hasOwnerRole(signers[0]);
        assertTrue(isOwner, "signers[0] does not have OWNER_ROLE");
    }

    function test_removeOwner() public {
        lotterie.removeOwner(signers[0]);
        bool isOwner = lotterie.hasOwnerRole(signers[0]);
        assertFalse(isOwner, "signers[0] have OWNER_ROLE");
    }

    function test_randomDrawBefore1DayWaiting() public {
        uint256 lastDraw = block.timestamp - 1 days;
        uint256 cooldown = 1 days;

        vm.warp(block.timestamp - 1 hours);
        uint256 currentTime = block.timestamp;

        vm.expectRevert(
            abi.encodeWithSelector(ILotterie.DrawCooldownNotExpired.selector, lastDraw, cooldown, currentTime)
        );
        lotterie.randomDraw();
    }

    function test_randomDraw() public {
        vm.warp(block.timestamp + 1 days);
        vm.recordLogs();
        uint256 requestId = lotterie.randomDraw();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (Vm.Log memory randomDrawLog, bool found) = _findLog(logs, keccak256("RandomDrawed(uint256)"));
        assertTrue(found, "RandomDrawed event missing");

        uint256 emittedRequestId = uint256(randomDrawLog.topics[1]);
        assertEq(emittedRequestId, requestId, "requestId should match event payload");
    }

    function test_randomDrawFulfillmentAndClaimFlow() public {
        vm.warp(block.timestamp + 1 days);
        goldToken.mint{value: 1 ether}();
        uint256 requestId = lotterie.randomDraw();

        assertEq(lotterie.getLastRequestId(), requestId, "last request id should match the recent draw");

        uint256 lotterieBalanceBefore = goldToken.balanceOf(address(lotterie));
        assertTrue(lotterieBalanceBefore > 0, "lottery should hold rewards before fulfillment");

        vm.recordLogs();
        vrfCoordinator.fulfillRandomWords(requestId, address(lotterie));

        address winner = lotterie.getResults(requestId);
        Vm.Log[] memory fulfillmentLogs = vm.getRecordedLogs();
        (Vm.Log memory winnerLog, bool winnerFound) = _findLog(fulfillmentLogs, keccak256("Winner(address)"));
        assertTrue(winnerFound, "Winner event missing");
        address emittedWinner = _topicToAddress(winnerLog.topics[1]);
        assertEq(emittedWinner, winner, "winner event payload mismatch");
        assertTrue(winner != address(0), "winner should not be the zero address");

        uint256 gains = lotterie.getGains(winner);
        assertEq(gains, lotterieBalanceBefore, "gains should equal the lottery balance");

        uint256 winnerBalanceBefore = goldToken.balanceOf(winner);

        vm.expectEmit(true, false, false, true, address(lotterie));
        emit GainClaimed(winner, gains);
        vm.prank(winner);
        lotterie.claim();

        assertEq(lotterie.getGains(winner), 0, "gains should reset after claim");
        assertEq(goldToken.balanceOf(winner), winnerBalanceBefore + gains, "winner balance should increase by gains");
        assertEq(
            goldToken.balanceOf(address(lotterie)),
            lotterieBalanceBefore - gains,
            "lottery balance should decrease by distributed gains"
        );
    }

    function test_claim_reverts_when_transfer_fails() public {
        vm.warp(block.timestamp + 1 days);
        goldToken.mint{value: 1 ether}();
        uint256 requestId = lotterie.randomDraw();
        vrfCoordinator.fulfillRandomWords(requestId, address(lotterie));

        address winner = lotterie.getResults(requestId);
        uint256 gains = lotterie.getGains(winner);

        vm.mockCall(
            address(goldToken), abi.encodeWithSelector(GoldToken.transfer.selector, winner, gains), abi.encode(false)
        );

        vm.prank(winner);
        vm.expectRevert(ILotterie.TransferFailed.selector);
        lotterie.claim();
    }

    function test_claim() public {
        vm.expectRevert(ILotterie.NoGainToClaim.selector);
        lotterie.claim();
    }

    function test_setVrfSubscriptionId() public {
        uint256 previous = lotterie.getVrfSubscriptionId();
        vm.expectEmit(true, true, false, false, address(lotterie));
        emit VrfSubscriptionUpdated(previous, 10);
        lotterie.setVrfSubscriptionId(10);
        uint256 vrfSubscriptionId = lotterie.getVrfSubscriptionId();
        assertEq(vrfSubscriptionId, 10, "vrfSubscriptionId should be 10");
    }

    function test_setVrfCoordinator() public {
        address previous = lotterie.getVrfCoordinator();
        vm.expectEmit(true, true, false, false, address(lotterie));
        emit VrfCoordinatorUpdated(previous, address(0x1));
        lotterie.setVrfCoordinator(address(0x1));
        address vrf = lotterie.getVrfCoordinator();
        assertEq(vrf, address(0x1), "vrfCoordinator should be 0x1");
    }

    function test_setKeyHash() public {
        bytes32 expectedKeyHash = keccak256(abi.encodePacked("test-key-hash"));
        vm.expectEmit(true, true, false, false, address(lotterie));
        emit KeyHashUpdated(lotterie.getKeyHash(), expectedKeyHash);
        lotterie.setKeyHash(expectedKeyHash);
        bytes32 keyHash = lotterie.getKeyHash();
        assertEq(keyHash, expectedKeyHash, "keyHash should match expected value");
    }

    function test_setCallbackGasLimit() public {
        vm.expectEmit(true, true, false, false, address(lotterie));
        emit CallbackGasLimitUpdated(lotterie.getCallbackGasLimit(), 10);
        lotterie.setCallbackGasLimit(10);
        uint32 gasLimit = lotterie.getCallbackGasLimit();
        assertEq(gasLimit, 10, "gasLimit should be 10");
    }

    function test_setRequestConfirmations() public {
        vm.expectEmit(true, true, false, false, address(lotterie));
        emit RequestConfirmationsUpdated(lotterie.getRequestConfirmations(), 10);
        lotterie.setRequestConfirmations(10);
        uint16 confirmations = lotterie.getRequestConfirmations();
        assertEq(confirmations, 10, "confirmations should be 10");
    }

    function test_setNumWords() public {
        vm.expectEmit(true, true, false, false, address(lotterie));
        emit NumWordsUpdated(lotterie.getNumWords(), 10);
        lotterie.setNumWords(10);
        uint32 numWords = lotterie.getNumWords();
        assertEq(numWords, 10, "numWords should be 10");
    }

    function test_setGoldToken() public {
        vm.expectEmit(true, true, false, false, address(lotterie));
        emit GoldTokenUpdated(address(goldToken), address(0x1));
        lotterie.setGoldToken(address(0x1));
        address goldTokenAddress = lotterie.getGoldToken();
        assertEq(goldTokenAddress, address(0x1), "goldToken should be 0x1");
    }

    function test_setRandomDrawCooldown() public {
        vm.expectEmit(true, true, false, false, address(lotterie));
        emit RandomDrawCooldownUpdated(lotterie.getRandomDrawCooldown(), 1 days + 1);
        lotterie.setRandomDrawCooldown(1 days + 1);
        assertEq(lotterie.getRandomDrawCooldown(), 1 days + 1, "cooldown should be updated");
    }

    function test_setVrfNativePayment() public {
        vm.expectEmit(true, true, false, false, address(lotterie));
        emit VrfNativePaymentUpdated(lotterie.getVrfNativePayment(), true);
        lotterie.setVrfNativePayment(true);
        assertTrue(lotterie.getVrfNativePayment(), "native payment should be true");
    }

    function test_initialize_emits_event() public {
        Lotterie implementation = new Lotterie(address(vrfCoordinator));
        uint256 subscription = vrfCoordinator.createSubscription();
        vm.expectEmit(true, true, true, true);
        emit LotterieInitialized(
            address(this),
            address(vrfCoordinator),
            address(goldToken),
            subscription,
            true,
            bytes32(uint256(0x1111)),
            50_000,
            2,
            1,
            86400
        );
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                Lotterie.initialize.selector,
                address(this),
                subscription,
                address(vrfCoordinator),
                true,
                bytes32(uint256(0x1111)),
                50_000,
                2,
                1,
                86400,
                address(goldToken)
            )
        );
    }

    function test_getLastRequestId() public view {
        uint256 requestId = lotterie.getLastRequestId();
        assertEq(requestId, uint256(0), "requestId should be 0");
    }

    function test_getGains() public view {
        uint256 gains = lotterie.getGains(address(this));
        assertEq(gains, 0, "gains should be 0");
    }

    function test_getResults() public view {
        address results = lotterie.getResults(0);
        assertEq(results, address(0), "results should be 0");
    }

    function test_upgradeTo_succeeds_for_owner() public {
        Lotterie newImplementation = new Lotterie(address(vrfCoordinator));

        UUPSUpgradeable(address(lotterie)).upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgradeTo_reverts_for_non_owner() public {
        Lotterie newImplementation = new Lotterie(address(vrfCoordinator));
        address nonOwner = address(0x9);

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), nonOwner, lotterie.OWNER_ROLE()
            )
        );
        vm.prank(nonOwner);
        UUPSUpgradeable(address(lotterie)).upgradeToAndCall(address(newImplementation), "");
    }

    function _findLog(Vm.Log[] memory logs, bytes32 topic) private pure returns (Vm.Log memory, bool) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                return (logs[i], true);
            }
        }

        Vm.Log memory empty;
        return (empty, false);
    }

    function _topicToAddress(bytes32 topic) private pure returns (address) {
        return address(uint160(uint256(topic)));
    }
}
