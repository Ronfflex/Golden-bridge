// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TokenBridge} from "../src/TokenBridge.sol";
import {ITokenBridge} from "../src/interfaces/ITokenBridge.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {TestLinkToken} from "./mock/TestLinkToken.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {MockCCIPRouter} from "@chainlink/contracts/src/v0.8/ccip/test/mocks/MockRouter.sol";

contract TokenBridgeFuzzTest is Test {
    TokenBridge public bridge;
    GoldToken public goldToken;
    TestLinkToken public linkToken;
    MockV3Aggregator public mockGold;
    MockV3Aggregator public mockEth;
    MockCCIPRouter public router;

    address public constant FEES_ADDRESS = address(0x2);
    uint64 public constant DEST_CHAIN_SELECTOR = 12345;
    uint64 public constant SOURCE_CHAIN_SELECTOR = 67890;

    function setUp() public {
        mockGold = new MockV3Aggregator(8, int256(100000000000));
        mockEth = new MockV3Aggregator(8, int256(50000000000));

        GoldToken goldTokenImpl = new GoldToken();
        ERC1967Proxy goldTokenProxy = new ERC1967Proxy(
            address(goldTokenImpl),
            abi.encodeWithSelector(GoldToken.initialize.selector, address(this), address(mockGold), address(mockEth))
        );
        goldToken = GoldToken(address(goldTokenProxy));

        linkToken = new TestLinkToken();
        linkToken.mint(address(this), 1000 ether);

        router = new MockCCIPRouter();

        // Mock ccipSend to bypass MockRouter's V1 extra-args decoding while still returning a message id
        vm.mockCall(
            address(router), abi.encodeWithSelector(router.ccipSend.selector), abi.encode(bytes32(uint256(0xabc)))
        );

        TokenBridge bridgeImpl = new TokenBridge(address(router));
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(
            address(bridgeImpl),
            abi.encodeWithSelector(
                TokenBridge.initialize.selector,
                address(this),
                address(linkToken),
                address(goldToken),
                DEST_CHAIN_SELECTOR
            )
        );
        bridge = TokenBridge(payable(address(bridgeProxy)));

        goldToken.setLotterieAddress(address(bridge));
        goldToken.setFeesAddress(FEES_ADDRESS);

        // Setup chain configuration
        bridge.setWhitelistedChain(
            DEST_CHAIN_SELECTOR,
            true,
            Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true}))
        );
        bridge.setWhitelistedSender(address(bridge), true);
    }

    /// @notice Fuzz test bridging with various token amounts
    function testFuzz_bridgeTokens_withVariousAmounts(uint96 mintAmount, uint88 bridgeAmount) public {
        vm.assume(mintAmount > 0.01 ether);
        vm.assume(mintAmount < 100 ether);
        vm.assume(bridgeAmount > 0);

        vm.deal(address(this), mintAmount);
        goldToken.mint{value: mintAmount}();

        uint256 balance = goldToken.balanceOf(address(this));
        vm.assume(bridgeAmount <= balance);

        uint256 bridgeBalanceBefore = goldToken.balanceOf(address(bridge));
        address recipient = address(0x9999);

        goldToken.approve(address(bridge), bridgeAmount);

        bytes32 messageId = bridge.bridgeTokens(recipient, bridgeAmount, ITokenBridge.PayFeesIn.Native);

        assertTrue(messageId != bytes32(0), "Router should return a message id");
        assertEq(goldToken.balanceOf(address(this)), balance - bridgeAmount, "Sender balance should decrease");
        assertEq(goldToken.balanceOf(address(bridge)), bridgeBalanceBefore + bridgeAmount, "Bridge should lock tokens");
    }

    /// @notice Fuzz test receiving messages with various data
    function testFuzz_ccipReceive_withVariousAmounts(uint88 amount, address receiver) public {
        vm.assume(amount > 0);
        vm.assume(amount < 1000 ether);
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(bridge));

        // Mint tokens and ensure bridge holds liquidity
        vm.deal(address(this), 100 ether);
        goldToken.mint{value: 10 ether}();
        uint256 available = goldToken.balanceOf(address(this));
        vm.assume(amount <= available);

        goldToken.transfer(address(bridge), amount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(goldToken), amount: amount});

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(address(bridge)),
            data: abi.encode(receiver),
            destTokenAmounts: tokenAmounts
        });

        bridge.setWhitelistedChain(
            SOURCE_CHAIN_SELECTOR,
            true,
            Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true}))
        );

        uint256 receiverBalanceBefore = goldToken.balanceOf(receiver);

        vm.prank(address(router));
        bridge.ccipReceive(message);

        uint256 receiverBalanceAfter = goldToken.balanceOf(receiver);
        assertEq(receiverBalanceAfter - receiverBalanceBefore, amount, "Receiver should get bridged tokens");
    }

    /// @notice Fuzz test whitelisting with random addresses
    function testFuzz_whitelistManagement(address sender1, address sender2, bool enable1, bool enable2) public {
        vm.assume(sender1 != address(0));
        vm.assume(sender2 != address(0));

        bridge.setWhitelistedSender(sender1, enable1);
        bridge.setWhitelistedSender(sender2, enable2);
        bridge.setWhitelistedChain(
            SOURCE_CHAIN_SELECTOR,
            true,
            Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true}))
        );

        // Verify state matches
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        Client.Any2EVMMessage memory msg1 = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(sender1),
            data: abi.encode(address(0x123)),
            destTokenAmounts: tokenAmounts
        });

        bool sender1Status = enable1;
        if (sender1 == sender2) {
            sender1Status = enable2; // latest assignment wins when addresses match
        }

        if (sender1Status) {
            vm.prank(address(router));
            bridge.ccipReceive(msg1);
        } else {
            vm.expectRevert(abi.encodeWithSelector(ITokenBridge.SenderNotWhitelisted.selector, sender1));
            vm.prank(address(router));
            bridge.ccipReceive(msg1);
        }

        // Also validate the second sender's final status
        Client.Any2EVMMessage memory msg2 = Client.Any2EVMMessage({
            messageId: bytes32(uint256(2)),
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(sender2),
            data: abi.encode(address(0x456)),
            destTokenAmounts: tokenAmounts
        });

        if (enable2) {
            vm.prank(address(router));
            bridge.ccipReceive(msg2);
        } else {
            vm.expectRevert(abi.encodeWithSelector(ITokenBridge.SenderNotWhitelisted.selector, sender2));
            vm.prank(address(router));
            bridge.ccipReceive(msg2);
        }
    }

    /// @notice Fuzz test gas limit configurations
    function testFuzz_gasLimitConfiguration(uint16 gasLimit) public {
        vm.assume(gasLimit > 10000);
        vm.assume(gasLimit < 5000000);

        uint64 testChain = 99999;

        bridge.setWhitelistedChain(
            testChain,
            true,
            Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: gasLimit, allowOutOfOrderExecution: true}))
        );

        // Verify configuration was set
        assertTrue(bridge.whitelistedChains(testChain), "Chain should be whitelisted");
    }

    /// @notice Fuzz test withdrawal with various amounts
    function testFuzz_withdraw_nativeToken(uint96 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 100 ether);

        vm.deal(address(bridge), amount);

        uint256 balanceBefore = address(this).balance;
        bridge.withdraw(address(this));
        uint256 balanceAfter = address(this).balance;

        assertEq(balanceAfter - balanceBefore, amount, "Should receive withdrawn amount");
    }

    /// @notice Fuzz test token withdrawal with various amounts
    function testFuzz_withdrawToken(uint96 mintAmount, uint88 withdrawAmount) public {
        vm.assume(mintAmount > 0.01 ether);
        vm.assume(mintAmount < 100 ether);
        vm.assume(withdrawAmount > 0);

        vm.deal(address(this), mintAmount);
        goldToken.mint{value: mintAmount}();

        uint256 balance = goldToken.balanceOf(address(this));
        vm.assume(withdrawAmount <= balance);

        goldToken.transfer(address(bridge), withdrawAmount);
        uint256 bridgeBalanceBefore = goldToken.balanceOf(address(bridge));

        uint256 balanceBefore = goldToken.balanceOf(address(this));
        bridge.withdrawToken(address(this), address(goldToken));
        uint256 balanceAfter = goldToken.balanceOf(address(this));
        uint256 bridgeBalanceAfter = goldToken.balanceOf(address(bridge));

        assertEq(balanceAfter - balanceBefore, bridgeBalanceBefore, "Should receive entire bridge balance");
        assertEq(bridgeBalanceAfter, 0, "Bridge balance should be zero after withdrawal");
    }

    /// @notice Fuzz test pause/unpause doesn't break state
    function testFuzz_pauseUnpause_stateIntegrity(uint8 iterations) public {
        vm.assume(iterations > 0);
        vm.assume(iterations <= 10);

        for (uint256 i = 0; i < iterations; i++) {
            bridge.pause();
            assertTrue(bridge.paused(), "Should be paused");

            bridge.unpause();
            assertFalse(bridge.paused(), "Should be unpaused");
        }
    }

    /// @notice Fuzz test that duplicate messages are rejected
    function testFuzz_rejectDuplicateMessages(bytes32 messageId, address receiver, uint88 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 100 ether);
        vm.assume(receiver != address(0));

        // Mint and transfer to bridge
        vm.deal(address(this), 10 ether);
        goldToken.mint{value: 10 ether}();
        goldToken.transfer(address(bridge), amount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(goldToken), amount: amount});

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: SOURCE_CHAIN_SELECTOR,
            sender: abi.encode(address(bridge)),
            data: abi.encode(receiver),
            destTokenAmounts: tokenAmounts
        });

        bridge.setWhitelistedChain(
            SOURCE_CHAIN_SELECTOR,
            true,
            Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true}))
        );
        bridge.setWhitelistedSender(address(bridge), true);

        vm.prank(address(router));
        bridge.ccipReceive(message);

        assertTrue(bridge.processedMessages(messageId), "Message should be marked as processed");

        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.MessageAlreadyProcessed.selector, messageId));
        vm.prank(address(router));
        bridge.ccipReceive(message);
    }

    /// @notice Fuzz test fee payment modes
    function testFuzz_feePaymentModes(uint88 amount, uint8 paymentMode) public {
        vm.assume(amount > 0.001 ether);
        vm.assume(amount < 10 ether);
        vm.assume(paymentMode <= 1); // 0 = Native, 1 = LINK

        vm.deal(address(this), amount);
        goldToken.mint{value: amount}();

        uint256 balance = goldToken.balanceOf(address(this));
        uint256 bridgeAmount = balance / 2;
        vm.assume(bridgeAmount > 0);

        goldToken.approve(address(bridge), bridgeAmount);

        uint256 bridgeBalanceBefore = goldToken.balanceOf(address(bridge));

        if (paymentMode == 0) {
            bridge.bridgeTokens(address(0x123), bridgeAmount, ITokenBridge.PayFeesIn.Native);
        } else {
            bridge.bridgeTokens(address(0x123), bridgeAmount, ITokenBridge.PayFeesIn.LINK);
        }

        assertEq(goldToken.balanceOf(address(bridge)), bridgeBalanceBefore + bridgeAmount, "Bridge should lock tokens");
    }

    receive() external payable {}
}
