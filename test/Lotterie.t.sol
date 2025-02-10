// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/Lotterie.sol";
import "../src/GoldToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract LotterieTest is Test {
    address[] public signers;

    GoldToken public goldToken;
    MockV3Aggregator public mockGold;
    MockV3Aggregator public mockETH;

    Lotterie public lotterie;
    VRFCoordinatorV2_5Mock public vrfCoordinator;

    function setUp() public {
        signers = [address(0x1), address(0x2), address(0x3)];

        mockGold = new MockV3Aggregator(8, int256(100000000000)); // 100.00 USD
        mockETH = new MockV3Aggregator(8, int256(50000000000)); // 50.00 USD

        GoldToken implementation1 = new GoldToken();
        ERC1967Proxy proxy1 = new ERC1967Proxy(
            address(implementation1),
            abi.encodeWithSelector(GoldToken.initialize.selector, address(this), address(mockGold), address(mockETH))
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
        goldToken.transfer(signers[0], 100);
        goldToken.transfer(signers[1], 100);
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

    function test_randomDrawBefore30Days() public {
        vm.expectRevert(Lotterie.OneRandomDrawPerMounth.selector);
        lotterie.randomDraw();
    }

    // function test_randomDraw() public {
    //     vm.warp(block.timestamp + 30 days);
    //     lotterie.randomDraw();
    // }

    function test_claim() public {
        vm.expectRevert("No gain to claim");
        lotterie.claim();
    }

    function test_setSubscriptionId() public {
        lotterie.setSubscriptionId(10);
        uint256 subscriptionId = lotterie.getSubscriptionId();
        assertEq(subscriptionId, 10, "subscriptionId should be 10");
    }

    function test_setVrfCoordinator() public {
        lotterie.setVrfCoordinator(address(0x1));
        address vrf = lotterie.getVrfCoordinator();
        assertEq(vrf, address(0x1), "vrfCoordinator should be 0x1");
    }

    function test_setKeyHash() public {
        lotterie.setKeyHash(bytes32("10"));
        bytes32 keyHash = lotterie.getKeyHash();
        assertEq(keyHash, bytes32("10"), "keyHash should be 10");
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
