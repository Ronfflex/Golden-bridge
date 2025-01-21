// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/GoldToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@chainlink/contracts/v0.8/tests/MockV3Aggregator.sol";

contract GoldTokenTest is Test {
    GoldToken public goldToken;
    address[] public signers;

    MockV3Aggregator public mockGold;
    MockV3Aggregator public mockETH;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    function setUp() public {
        signers = [address(0x1), address(0x2), address(0x3)];

        mockGold = new MockV3Aggregator(8, int256(100000000000)); // 100.00 USD
        mockETH = new MockV3Aggregator(8, int256(50000000000)); // 50.00 USD

        GoldToken implementation = new GoldToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(GoldToken.initialize.selector, 
            address(this),
            address(mockGold),
            address(mockETH)
            )
        );
        goldToken = GoldToken(address(proxy));
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
        assertEq(fees, uint(5));
    }

    function test_mintValueZero() public {
        vm.expectRevert("GoldToken: mint value must be greater than 0");
        goldToken.mint{value: 0}();
    }

    function test_mintGoldValueZero() public {
        vm.expectRevert("GoldToken: gold amount must be greater than 0");
        goldToken.mint{value: 1}();
    }

    function test_mint() public {
        goldToken.mint{value: 10000}();
        uint256 balance = goldToken.balanceOf(address(this));
        assertEq(balance, 5000); // 1 GOLD = 0.5 ETH
        uint256 contractBalance = address(goldToken).balance;
        assertEq(balance, 5000);
        assertEq(contractBalance, 10000);
    }

    function test_burn() public {
        goldToken.mint{value: 10000}();
        uint256 balance = goldToken.balanceOf(address(this));
        goldToken.burn(balance);
        balance = goldToken.balanceOf(address(this));
        assertEq(balance, 0);
    }

    function test_claimEth() public {
        goldToken.mint{value: 10000}();
        goldToken.claimEth();
    }

    fallback() external payable{ }
    receive() external payable{ }
}
