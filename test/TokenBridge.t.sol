// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {ITokenBridge} from "../src/interfaces/ITokenBridge.sol";
import {TokenBridge} from "../src/TokenBridge.sol";
import {GoldToken} from "../src/GoldToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockLinkToken} from "@chainlink/contracts/src/v0.8/mocks/MockLinkToken.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockCCIPRouter} from "@chainlink/contracts/src/v0.8/ccip/test/mocks/MockRouter.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract TokenBridgeTest is Test {
    // Constants for roles and chain selectors
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    uint64 public constant ETHEREUM_CHAIN_SELECTOR = 1;
    uint64 public constant BSC_CHAIN_SELECTOR = 2;

    // Core contracts
    TokenBridge public tokenBridge;
    GoldToken public goldToken;
    MockLinkToken public linkToken;
    MockCCIPRouter public router;

    // Test addresses
    address[] public signers;
    address public owner;
    address public nonOwner;

    // Price feeds for GoldToken
    MockV3Aggregator public goldAggregator;
    MockV3Aggregator public ethAggregator;

    function setUp() public {
        // Setup accounts
        owner = address(this);
        nonOwner = address(0xdead);
        signers = [address(0x1), address(0x2), address(0x3)];
        vm.deal(owner, 100 ether);
        vm.deal(nonOwner, 100 ether);
        for (uint256 i = 0; i < signers.length; i++) {
            vm.deal(signers[i], 100 ether);
        }

        uint256 id;
        assembly {
            id := chainid()
        }
        if (id == 31337) {
            // Local network
            goldAggregator = new MockV3Aggregator(8, int256(100000000000)); // 100.00 USD
            ethAggregator = new MockV3Aggregator(8, int256(50000000000)); // 50.00 USD
        } else {
            // Mainnet fork
            goldAggregator = MockV3Aggregator(0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6); // gold / USD
            ethAggregator = MockV3Aggregator(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // ETH / USD
        }

        // Deploy GoldToken with proxy
        GoldToken implementation = new GoldToken();
        ERC1967Proxy goldTokenProxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                GoldToken.initialize.selector, owner, address(goldAggregator), address(ethAggregator)
            )
        );
        goldToken = GoldToken(address(goldTokenProxy));

        // Deploy mock LINK and Router
        linkToken = new MockLinkToken();
        router = new MockCCIPRouter();

        // Deploy TokenBridge with proxy
        TokenBridge implementation2 = new TokenBridge(address(router));
        ERC1967Proxy tokenBridgeProxy = new ERC1967Proxy(
            address(implementation2),
            abi.encodeWithSelector(
                TokenBridge.initialize.selector, owner, address(linkToken), address(goldToken), BSC_CHAIN_SELECTOR
            )
        );
        tokenBridge = TokenBridge(payable(address(tokenBridgeProxy)));

        // Setup initial states - IMPORTANT: proper order
        goldToken.setFeesAddress(address(this));
        goldToken.setLotterieAddress(address(this));
        goldToken.mint{value: 10 ether}();

        linkToken.setBalance(address(tokenBridge), 100 ether);
        vm.deal(address(tokenBridge), 100 ether);

        // Whitelist chains and senders
        tokenBridge.setWhitelistedChain(
            BSC_CHAIN_SELECTOR,
            true,
            Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true}))
        );
        tokenBridge.setWhitelistedSender(address(this), true);
    }

    function _setupLinkBalances() internal {
        // Make sure our test contract has enough LINK
        linkToken.setBalance(address(this), 1000 ether);
        // Set bridge's balance
        linkToken.setBalance(address(tokenBridge), 100 ether);
    }

    function _setupTokens() internal {
        goldToken.mint{value: 10 ether}();
        goldToken.transfer(address(tokenBridge), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialization() public view {
        assertEq(address(tokenBridge.goldToken()), address(goldToken));
        assertEq(address(tokenBridge.link()), address(linkToken));
        assertEq(tokenBridge.destinationChainSelector(), BSC_CHAIN_SELECTOR);
        assertTrue(tokenBridge.hasOwnerRole(owner));
        assertTrue(tokenBridge.whitelistedChains(BSC_CHAIN_SELECTOR));
    }

    function test_cannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        tokenBridge.initialize(owner, address(linkToken), address(goldToken), BSC_CHAIN_SELECTOR);
    }

    function test_cannotInitializeWithZeroAddresses() public {
        TokenBridge implementation = new TokenBridge(address(router));

        // Test with zero LINK address
        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.InvalidSender.selector, address(0)));
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                TokenBridge.initialize.selector,
                owner,
                address(0), // zero LINK address
                address(goldToken),
                BSC_CHAIN_SELECTOR
            )
        );

        // Test with zero GoldToken address
        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.InvalidSender.selector, address(0)));
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                TokenBridge.initialize.selector,
                owner,
                address(linkToken),
                address(0), // zero GoldToken address
                BSC_CHAIN_SELECTOR
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                              ACCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onlyOwnerCanAddOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), nonOwner, OWNER_ROLE
            )
        );
        tokenBridge.addOwner(signers[0]);
    }

    function test_addAndRemoveOwner() public {
        tokenBridge.addOwner(signers[0]);
        assertTrue(tokenBridge.hasOwnerRole(signers[0]));

        tokenBridge.removeOwner(signers[0]);
        assertFalse(tokenBridge.hasOwnerRole(signers[0]));
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_bridgeTokensWithLink() public {
        _setupLinkBalances();
        uint256 amount = 1 ether;
        address receiver = address(0x9999); // Use a normal address instead of precompile

        // Record initial balance
        uint256 initialBridgeBalance = goldToken.balanceOf(address(tokenBridge));
        uint256 initialSenderBalance = goldToken.balanceOf(address(this));

        // Approve tokens
        goldToken.approve(address(tokenBridge), amount);

        // Make sure the router ccipSend function will be called correctly
        // This mocks the CCIP router's behavior
        bytes32 expectedMsgId = bytes32(uint256(123456));
        vm.mockCall(address(router), abi.encodeWithSelector(router.ccipSend.selector), abi.encode(expectedMsgId));

        // Bridge tokens
        bytes32 returnedId = tokenBridge.bridgeTokens(receiver, amount, ITokenBridge.PayFeesIn.LINK);

        // Verify messageId
        assertEq(returnedId, expectedMsgId);

        // Verify state changes
        assertEq(
            goldToken.balanceOf(address(tokenBridge)), initialBridgeBalance + amount, "Bridge balance should increase"
        );
        assertEq(goldToken.balanceOf(address(this)), initialSenderBalance - amount, "Sender balance should decrease");

        // Verify the token was approved to the router
        assertEq(
            goldToken.allowance(address(tokenBridge), address(router)), amount, "Token should be approved to router"
        );
    }

    function test_bridgeTokensWithNative() public {
        uint256 amount = 1 ether;
        address receiver = address(0x9999);

        // Record initial balance
        uint256 initialBridgeBalance = goldToken.balanceOf(address(tokenBridge));
        uint256 initialSenderBalance = goldToken.balanceOf(address(this));

        // Approve tokens
        goldToken.approve(address(tokenBridge), amount);

        // Configure mock router to return a messageId for the call
        bytes32 messageId = bytes32(uint256(123456));
        vm.mockCall(address(router), abi.encodeWithSelector(router.ccipSend.selector), abi.encode(messageId));

        // Bridge tokens with native token fees
        bytes32 returnedId = tokenBridge.bridgeTokens{value: 1 ether}(receiver, amount, ITokenBridge.PayFeesIn.Native);

        // Verify messageId
        assertEq(returnedId, messageId);

        // Verify state changes
        assertEq(
            goldToken.balanceOf(address(tokenBridge)), initialBridgeBalance + amount, "Bridge balance should increase"
        );
        assertEq(goldToken.balanceOf(address(this)), initialSenderBalance - amount, "Sender balance should decrease");
    }

    function test_cannotBridgeZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.InvalidAmount.selector, 0));
        tokenBridge.bridgeTokens(signers[0], 0, ITokenBridge.PayFeesIn.LINK);
    }

    function test_cannotBridgeWhenPaused() public {
        tokenBridge.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        tokenBridge.bridgeTokens(signers[0], 1 ether, ITokenBridge.PayFeesIn.LINK);
    }

    function test_cannotBridgeToUnwhitelistedChain() public {
        tokenBridge.setWhitelistedChain(BSC_CHAIN_SELECTOR, false, "");

        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.ChainNotWhitelisted.selector, BSC_CHAIN_SELECTOR));
        tokenBridge.bridgeTokens(signers[0], 1 ether, ITokenBridge.PayFeesIn.LINK);
    }

    /*//////////////////////////////////////////////////////////////
                        MESSAGE RECEIVING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ccipReceive() public {
        _setupTokens();

        address recipient = signers[0];
        uint256 amount = 0.5 ether;

        // Record initial balances
        uint256 initialRecipientBalance = goldToken.balanceOf(recipient);
        uint256 initialBridgeBalance = goldToken.balanceOf(address(tokenBridge));

        // Create a destTokenAmounts array with the GoldToken
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({token: address(goldToken), amount: amount});

        // Create a mock message
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: BSC_CHAIN_SELECTOR,
            sender: abi.encode(address(this)),
            data: abi.encode(recipient), // Receiver encoded in data field
            destTokenAmounts: destTokenAmounts
        });

        // Simulate router calling ccipReceive
        vm.prank(address(router));
        tokenBridge.ccipReceive(message);

        // Verify the message was processed
        assertTrue(tokenBridge.processedMessages(message.messageId));

        // Verify token balances - recipient should get their tokens
        assertEq(goldToken.balanceOf(recipient), initialRecipientBalance + amount, "Recipient should receive tokens");
        assertEq(
            goldToken.balanceOf(address(tokenBridge)), initialBridgeBalance - amount, "Bridge balance should decrease"
        );
    }

    function test_cannotReceiveSameMessageTwice() public {
        _setupTokens();

        // Create destTokenAmounts array
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({token: address(goldToken), amount: 0.5 ether});

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: BSC_CHAIN_SELECTOR,
            sender: abi.encode(address(this)),
            data: abi.encode(signers[0]), // Receiver
            destTokenAmounts: destTokenAmounts
        });

        vm.startPrank(address(router));
        tokenBridge.ccipReceive(message);

        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.MessageAlreadyProcessed.selector, message.messageId));
        tokenBridge.ccipReceive(message);
        vm.stopPrank();
    }

    function test_cannotReceiveFromUnwhitelistedChain() public {
        _setupTokens();
        uint64 unwhitelistedChainSelector = 999;

        // Create destTokenAmounts array
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({token: address(goldToken), amount: 0.5 ether});

        // Create a message from an unwhitelisted chain
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: unwhitelistedChainSelector, // Using unwhitelisted chain
            sender: abi.encode(address(this)),
            data: abi.encode(signers[0]), // Receiver
            destTokenAmounts: destTokenAmounts
        });

        // Try to receive the message
        vm.prank(address(router));
        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.ChainNotWhitelisted.selector, unwhitelistedChainSelector));
        tokenBridge.ccipReceive(message);
    }

    function test_cannotReceiveFromUnwhitelistedSender() public {
        _setupTokens();
        address unwhitelistedSender = address(0xbad);

        // Create destTokenAmounts array
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({token: address(goldToken), amount: 0.5 ether});

        // Create a message from an unwhitelisted sender
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: BSC_CHAIN_SELECTOR,
            sender: abi.encode(unwhitelistedSender), // Using unwhitelisted sender
            data: abi.encode(signers[0]), // Receiver
            destTokenAmounts: destTokenAmounts
        });

        // Try to receive the message
        vm.prank(address(router));
        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.SenderNotWhitelisted.selector, unwhitelistedSender));
        tokenBridge.ccipReceive(message);
    }

    function test_cannotReceiveWhenPaused() public {
        _setupTokens();
        tokenBridge.pause();

        // Create destTokenAmounts array
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({token: address(goldToken), amount: 0.5 ether});

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: BSC_CHAIN_SELECTOR,
            sender: abi.encode(address(this)),
            data: abi.encode(signers[0]), // Receiver
            destTokenAmounts: destTokenAmounts
        });

        vm.prank(address(router));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        tokenBridge.ccipReceive(message);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pause() public {
        assertFalse(tokenBridge.paused());

        tokenBridge.pause();
        assertTrue(tokenBridge.paused());

        tokenBridge.unpause();
        assertFalse(tokenBridge.paused());
    }

    function test_setWhitelistedChain() public {
        uint64 newChain = 3;
        bytes memory args =
            Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: true}));

        tokenBridge.setWhitelistedChain(newChain, true, args);
        assertTrue(tokenBridge.whitelistedChains(newChain));

        tokenBridge.setWhitelistedChain(newChain, false, "");
        assertFalse(tokenBridge.whitelistedChains(newChain));
    }

    function test_setWhitelistedSender() public {
        address newSender = signers[0];

        tokenBridge.setWhitelistedSender(newSender, true);
        assertTrue(tokenBridge.whitelistedSenders(newSender));

        tokenBridge.setWhitelistedSender(newSender, false);
        assertFalse(tokenBridge.whitelistedSenders(newSender));
    }

    function test_cannotSetZeroChainSelector() public {
        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.InvalidChainSelector.selector, 0));
        tokenBridge.setWhitelistedChain(0, true, "");
    }

    function test_cannotSetZeroAddressSender() public {
        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.InvalidSender.selector, address(0)));
        tokenBridge.setWhitelistedSender(address(0), true);
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_withdraw() public {
        uint256 initialBalance = address(this).balance;
        uint256 bridgeBalance = address(tokenBridge).balance;

        tokenBridge.withdraw(address(this));

        assertEq(address(tokenBridge).balance, 0);
        assertEq(address(this).balance, initialBalance + bridgeBalance);
    }

    function test_withdrawToken() public {
        uint256 initialBalance = linkToken.balanceOf(address(this));
        uint256 bridgeBalance = linkToken.balanceOf(address(tokenBridge));

        tokenBridge.withdrawToken(address(this), address(linkToken));

        assertEq(linkToken.balanceOf(address(tokenBridge)), 0);
        assertEq(linkToken.balanceOf(address(this)), initialBalance + bridgeBalance);
    }

    function test_cannotWithdrawZeroAmount() public {
        // Empty the bridge's balance first
        address(tokenBridge).balance;
        vm.prank(owner);
        tokenBridge.withdraw(payable(owner));

        // Try to withdraw again
        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.InvalidAmount.selector, 0));
        tokenBridge.withdraw(payable(owner));
    }

    function test_cannotWithdrawTokenZeroAmount() public {
        // Empty the bridge's token balance first
        tokenBridge.withdrawToken(address(this), address(linkToken));

        // Try to withdraw again
        vm.expectRevert(abi.encodeWithSelector(ITokenBridge.InvalidAmount.selector, 0));
        tokenBridge.withdrawToken(address(this), address(linkToken));
    }

    function test_failedEthWithdrawal() public {
        // Create a contract that rejects ETH
        ContractThatRejectsEth rejectingContract = new ContractThatRejectsEth();

        vm.deal(address(tokenBridge), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenBridge.FailedToWithdrawEth.selector, address(this), address(rejectingContract), 1 ether
            )
        );
        tokenBridge.withdraw(address(rejectingContract));
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_canUpgrade() public {
        TokenBridge newImplementation = new TokenBridge(address(router));

        vm.prank(owner);
        UUPSUpgradeable(address(tokenBridge)).upgradeToAndCall(address(newImplementation), "");
    }

    function test_cannotUpgradeUnauthorized() public {
        TokenBridge newImplementation = new TokenBridge(address(router));

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), nonOwner, OWNER_ROLE
            )
        );
        UUPSUpgradeable(address(tokenBridge)).upgradeToAndCall(address(newImplementation), "");
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getBalances() public view {
        // Test getLinkBalance
        uint256 expectedLinkBalance = linkToken.balanceOf(address(tokenBridge));
        assertEq(tokenBridge.getLinkBalance(), expectedLinkBalance);

        // Test getGoldTokenBalance
        uint256 expectedGoldBalance = goldToken.balanceOf(address(tokenBridge));
        assertEq(tokenBridge.getGoldTokenBalance(), expectedGoldBalance);
    }

    function test_supportsInterface() public view {
        // IAccessControl interface id
        bytes4 accessControlInterfaceId = 0x7965db0b;
        assertTrue(tokenBridge.supportsInterface(accessControlInterfaceId));

        // Test a random interface id that we don't support
        bytes4 randomInterfaceId = 0x12345678;
        assertFalse(tokenBridge.supportsInterface(randomInterfaceId));
    }

    receive() external payable {}
}

// Contract that rejects ETH for test_failedEthWithdrawal
contract ContractThatRejectsEth {
    receive() external payable {
        revert("I reject ETH");
    }
}
