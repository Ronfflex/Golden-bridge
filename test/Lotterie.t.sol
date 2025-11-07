// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Lotterie} from "../src/Lotterie.sol";
import {ILotterie} from "../src/interfaces/ILotterie.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract LotterieTest is Test {
    address[] public signers;

    GoldToken public goldToken;
    MockV3Aggregator public mockGold;
    MockV3Aggregator public mockEth;

    Lotterie public lotterie;
    VRFCoordinatorV2_5Mock public vrfCoordinator;

    function setUp() public {
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
                bytes32(0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae),
                100000,
                3,
                1,
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
        vm.warp(block.timestamp - 1 hours);
        vm.expectRevert(ILotterie.OneRandomDrawPerDay.selector);
        lotterie.randomDraw();
    }

    function test_randomDraw() public {
        vm.warp(block.timestamp + 1 days);
        console2.log("Current time:", block.timestamp + 1 days);
        lotterie.randomDraw();
    }

    function test_claim() public {
        vm.expectRevert(ILotterie.NoGainToClaim.selector);
        lotterie.claim();
    }

    function test_setVrfSubscriptionId() public {
        lotterie.setVrfSubscriptionId(10);
        uint256 vrfSubscriptionId = lotterie.getVrfSubscriptionId();
        assertEq(vrfSubscriptionId, 10, "vrfSubscriptionId should be 10");
    }

    function test_setVrfCoordinator() public {
        lotterie.setVrfCoordinator(address(0x1));
        address vrf = lotterie.getVrfCoordinator();
        assertEq(vrf, address(0x1), "vrfCoordinator should be 0x1");
    }

    function test_setKeyHash() public {
        bytes32 expectedKeyHash = keccak256(abi.encodePacked("test-key-hash"));
        lotterie.setKeyHash(expectedKeyHash);
        bytes32 keyHash = lotterie.getKeyHash();
        assertEq(keyHash, expectedKeyHash, "keyHash should match expected value");
    }

    function test_setCallbackGasLimit() public {
        lotterie.setCallbackGasLimit(10);
        uint32 gasLimit = lotterie.getCallbackGasLimit();
        assertEq(gasLimit, 10, "gasLimit should be 10");
    }

    function test_setRequestConfirmations() public {
        lotterie.setRequestConfirmations(10);
        uint16 confirmations = lotterie.getRequestConfirmations();
        assertEq(confirmations, 10, "confirmations should be 10");
    }

    function test_setNumWords() public {
        lotterie.setNumWords(10);
        uint32 numWords = lotterie.getNumWords();
        assertEq(numWords, 10, "numWords should be 10");
    }

    function test_setGoldToken() public {
        lotterie.setGoldToken(address(0x1));
        address goldTokenAddress = lotterie.getGoldToken();
        assertEq(goldTokenAddress, address(0x1), "goldToken should be 0x1");
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
}
