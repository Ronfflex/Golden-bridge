// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/GoldToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract GoldTokenTest is Test {
    GoldToken public goldToken;
    address[] public signers;

    MockV3Aggregator public goldAggregator;
    MockV3Aggregator public ethAggregator;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    function setUp() public {
        uint256 id;
        assembly {
            id := chainid()
        }
        if (id == 31337) { // Local network
            goldAggregator = new MockV3Aggregator(8, int256(100000000000)); // 100.00 USD
            ethAggregator = new MockV3Aggregator(8, int256(50000000000)); // 50.00 USD
        } else { // Mainnet fork
            goldAggregator = MockV3Aggregator(0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6); // gold / USD
            ethAggregator = MockV3Aggregator(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // ETH / USD
        }

        signers = [address(0x1), address(0x2), address(0x3)];
        vm.deal(signers[0], 10 ether);

        GoldToken implementation = new GoldToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(GoldToken.initialize.selector, address(this), address(goldAggregator), address(ethAggregator))
        );
        goldToken = GoldToken(address(proxy));
        goldToken.setLotterieAddress(address(10));
    }

    function test_addOwner() public {
        goldToken.addOwner(signers[0]);
        bool isOwner = goldToken.hasOwnerRole(signers[0]);
        assertTrue(isOwner, "signers[0] does not have OWNER_ROLE");
    }

    function test_removeOwner() public {
        goldToken.removeOwner(signers[0]);
        bool isOwner = goldToken.hasOwnerRole(signers[0]);
        assertFalse(isOwner, "signers[0] have OWNER_ROLE");
    }

    function test_pause() public {
        goldToken.pause();

        vm.expectRevert();
        goldToken.mint();

        vm.expectRevert();
        goldToken.burn(0);

        goldToken.unpause();
        bool isPaused = goldToken.paused();
        assertFalse(isPaused, "contract should be not paused");
    }

    function test_setFeesAddress() public {
        address feesAddress = goldToken.getFeesAddress();
        assertEq(feesAddress, address(this));

        goldToken.setFeesAddress(address(signers[0]));

        feesAddress = goldToken.getFeesAddress();
        assertEq(feesAddress, address(signers[0]));
    }

    function test_getFees() public view {
        uint256 fees = goldToken.getFees();
        assertEq(fees, uint256(5));
    }

    function test_mintValueZero() public {
        vm.expectRevert(GoldToken.ValueMustBeGreaterThanZero.selector);
        goldToken.mint{value: 0}();
    }

    function test_mintGoldValueZero() public {
        vm.expectRevert(GoldToken.AmountMustBeGreaterThanZero.selector);
        goldToken.mint{value: 1}();
    }

    function test_mint() public {
        vm.startPrank(signers[0]);
        uint256 contractBefore = address(goldToken).balance;
        goldToken.mint{value: 1 ether}();
        uint256 balance = goldToken.balanceOf(address(signers[0]));
        assertTrue(balance > 0);
        uint256 contractBalance = address(goldToken).balance;
        assertEq(contractBalance, contractBefore + 1 ether);
        vm.stopPrank();
    }

    function test_burn() public {
        goldToken.mint{value: 10000}();
        uint256 balance = goldToken.balanceOf(address(signers[0]));
        goldToken.burn(balance);
        balance = goldToken.balanceOf(address(signers[0]));
        assertEq(balance, 0);
    }

    function test_transfer() public {
        goldToken.mint{value: 10000}(); // Receive 5000 GLD
        goldToken.transfer(address(signers[0]), 1000);
        uint256 balance = goldToken.balanceOf(address(this));
        assertTrue(balance > 0);
    }

    function test_transferAmountZero() public {
        goldToken.mint{value: 10000}(); // Receive 5000 GLD
        vm.expectRevert(GoldToken.AmountMustBeGreaterThanZero.selector);
        goldToken.transfer(address(signers[0]), 0);
    }

    function test_claimEth() public {
        goldToken.mint{value: 10000}();
        goldToken.claimEth();
    }

    function test_getUsers() public {
        goldToken.mint{value: 10000}();
        address[] memory users = goldToken.getUsers();
        assertEq(users.length, 1);
        assertEq(users[0], address(this));
    }

    function test_getTimestamps() public {
        goldToken.mint{value: 10000}();
        (address[] memory users, uint256[] memory timestamps) = goldToken.getTimestamps();
        assertEq(users.length, 1);
        assertEq(users[0], address(this));
        assertEq(timestamps.length, 1);
        assertEq(timestamps[0], block.timestamp);
    }

    fallback() external payable {}
    receive() external payable {}
}
