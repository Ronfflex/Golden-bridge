// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/Lotterie.sol";
import "../src/GoldToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract LotterieTest is Test {
    address[] public signers;

    GoldToken public goldToken;
    MockV3Aggregator public mockGold;
    MockV3Aggregator public mockETH;

    Lotterie public lotterie;
    VRFCoordinatorV2Mock public vrfCoordinator;

    function setUp() public{
        signers = [address(0x1), address(0x2), address(0x3)];

        mockGold = new MockV3Aggregator(8, int256(100000000000)); // 100.00 USD
        mockETH = new MockV3Aggregator(8, int256(50000000000)); // 50.00 USD

        GoldToken implementation1 = new GoldToken();
        ERC1967Proxy proxy1 = new ERC1967Proxy(
            address(implementation1),
            abi.encodeWithSelector(GoldToken.initialize.selector, address(this), address(mockGold), address(mockETH))
        );
        goldToken = GoldToken(address(proxy1));

        vrfCoordinator = new VRFCoordinatorV2Mock(100000000000000000, 1000000000);
        uint64 subscription = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subscription, 1000000000000000000);

        Lotterie implementation2 = new Lotterie(address(vrfCoordinator));
        ERC1967Proxy proxy2 = new ERC1967Proxy(
            address(implementation2),
            abi.encodeWithSelector(Lotterie.initialize.selector, address(this), subscription, address(vrfCoordinator), bytes32(0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc), 100000, 3, 1, address(goldToken))
        );
        lotterie = Lotterie(address(proxy2));

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
}