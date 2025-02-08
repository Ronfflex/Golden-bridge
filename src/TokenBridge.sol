// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {ITokenBridge} from "./interfaces/ITokenBridge.sol";

/**
 * @title TokenBridge
 * @notice A cross-chain bridge implementation for GoldToken using Chainlink's CCIP
 * @dev This contract enables secure token transfers between Ethereum and BSC networks.
 * Key features:
 * - Uses Chainlink's CCIP for secure cross-chain messaging
 * - Supports both LINK and native token (ETH/BNB) for fee payments
 * - Includes whitelist controls for chains and senders
 * - Implements pausable functionality for emergency stops
 * @custom:security-contact security@goldbridge.com
 */
contract TokenBridge is CCIPReceiver, OwnerIsCreator, ITokenBridge {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Chain selector for the destination chain (BSC)
    /// @dev Immutable value set at deployment, cannot be changed
    uint64 public immutable override destinationChainSelector;

    /// @notice Address of the GoldToken contract
    /// @dev Immutable value set at deployment, cannot be changed
    address public immutable override goldToken;

    /// @notice Address of the LINK token used for fees
    /// @dev Immutable value set at deployment, cannot be changed
    address public immutable override link;

    /// @notice Mapping to track processed CCIP messages to prevent duplicates
    /// @dev Maps messageId to processing status
    mapping(bytes32 => bool) public override processedMessages;

    /// @notice Mapping of whitelisted chains that can interact with this contract
    /// @dev Maps chain selector to whitelist status
    mapping(uint64 => bool) public override whitelistedChains;

    /// @notice Mapping of whitelisted sender addresses on other chains
    /// @dev Maps sender address to whitelist status
    mapping(address => bool) public override whitelistedSenders;

    /// @notice Gas limit for cross-chain operations
    /// @dev Can be modified by owner to adapt to network conditions
    uint256 private _ccipGasLimit;

    /// @notice Flag to allow out-of-order message execution
    /// @dev Controls whether messages must be processed in sequence
    bool private _allowOutOfOrderExecution;

    /// @notice Flag indicating if the bridge is paused
    /// @dev Used for emergency stops
    bool private _paused;

    /**
     * @notice Initializes the bridge contract
     * @dev Sets up initial configuration including whitelisting the destination chain
     * All parameters must be non-zero addresses to prevent configuration errors
     * @param _router The address of the CCIP router contract
     * @param _link The address of the LINK token contract
     * @param _goldToken The address of the GoldToken contract
     * @param _destinationChainSelector The chain selector for the destination chain (BSC)
     */
    constructor(address _router, address _link, address _goldToken, uint64 _destinationChainSelector)
        CCIPReceiver(_router)
    {
        if (_router == address(0) || _link == address(0) || _goldToken == address(0)) {
            revert InvalidSender(address(0));
        }

        link = _link;
        goldToken = _goldToken;
        destinationChainSelector = _destinationChainSelector;

        whitelistedChains[_destinationChainSelector] = true;
        emit ChainWhitelisted(_destinationChainSelector);

        _ccipGasLimit = 200_000; // Default gas limit
        _allowOutOfOrderExecution = true; // Default to allow out of order execution
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @inheritdoc ITokenBridge
     */
    function bridgeTokensPayLink(address receiver, uint256 amount) external override returns (bytes32 messageId) {
        return _bridgeTokens(receiver, amount, link);
    }

    /**
     * @inheritdoc ITokenBridge
     */
    function bridgeTokensPayNative(address receiver, uint256 amount)
        external
        payable
        override
        returns (bytes32 messageId)
    {
        return _bridgeTokens(receiver, amount, address(0));
    }

    /**
     * @notice Internal implementation of token bridging logic
     * @dev Handles token transfer and CCIP message creation
     * Steps:
     * 1. Validates inputs and contract state
     * 2. Transfers tokens from sender to bridge
     * 3. Creates and sends CCIP message
     * 4. Handles fee payment (LINK or native)
     * @param receiver The address that will receive tokens
     * @param amount The amount of tokens to bridge
     * @param feeToken The token used to pay CCIP fees (LINK or native token)
     * @return messageId The unique identifier for this bridge transaction
     */
    function _bridgeTokens(address receiver, uint256 amount, address feeToken) internal returns (bytes32 messageId) {
        if (_paused) revert BridgePausedError();
        if (amount == 0) revert InvalidAmount(amount);
        if (!whitelistedChains[destinationChainSelector]) {
            revert ChainNotWhitelisted(destinationChainSelector);
        }

        IERC20(goldToken).safeTransferFrom(msg.sender, address(this), amount);

        Client.EVM2AnyMessage memory message = _buildCCIPMessage(receiver, amount, feeToken);

        uint256 fees = IRouterClient(getRouter()).getFee(destinationChainSelector, message);

        if (feeToken == address(0)) {
            if (msg.value < fees) revert NotEnoughBalance(msg.value, fees);
        } else {
            if (IERC20(feeToken).balanceOf(address(this)) < fees) {
                revert NotEnoughBalance(IERC20(feeToken).balanceOf(address(this)), fees);
            }
            IERC20(feeToken).approve(getRouter(), fees);
        }

        messageId = IRouterClient(getRouter()).ccipSend{value: feeToken == address(0) ? fees : 0}(
            destinationChainSelector, message
        );

        emit TokensBridged(messageId, msg.sender, receiver, amount, destinationChainSelector, feeToken, fees);
    }

    /**
     * @notice Builds CCIP message for cross-chain communication
     * @dev Creates an EVM2AnyMessage struct with necessary parameters
     * Uses configured gas limit and out-of-order execution settings
     * @param receiver The address that will receive tokens
     * @param amount The amount of tokens being transferred
     * @param feeToken The token used for paying fees
     * @return Client.EVM2AnyMessage The constructed CCIP message
     */
    function _buildCCIPMessage(address receiver, uint256 amount, address feeToken)
        internal
        view
        returns (Client.EVM2AnyMessage memory)
    {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: _ccipGasLimit, allowOutOfOrderExecution: _allowOutOfOrderExecution})
            ),
            feeToken: feeToken
        });
    }

    /**
     * @notice Processes incoming CCIP messages
     * @dev Implements CCIPReceiver's _ccipReceive
     * Validates message authenticity and handles token transfer
     * @param message The CCIP message containing transfer details
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        if (_paused) revert BridgePausedError();
        if (processedMessages[message.messageId]) {
            revert MessageAlreadyProcessed(message.messageId);
        }
        if (!whitelistedChains[message.sourceChainSelector]) {
            revert ChainNotWhitelisted(message.sourceChainSelector);
        }

        address sender = abi.decode(message.sender, (address));
        if (!whitelistedSenders[sender]) revert SenderNotWhitelisted(sender);

        (address receiver, uint256 amount) = abi.decode(message.data, (address, uint256));
        if (amount == 0) revert InvalidAmount(amount);

        processedMessages[message.messageId] = true;

        IERC20(goldToken).safeTransfer(receiver, amount);

        emit TokensReceived(message.messageId, receiver, amount, message.sourceChainSelector);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @inheritdoc ITokenBridge
     */
    function setWhitelistedChain(uint64 chainSelector, bool enabled) external override onlyOwner {
        whitelistedChains[chainSelector] = enabled;
        if (enabled) {
            emit ChainWhitelisted(chainSelector);
        } else {
            emit ChainRemoved(chainSelector);
        }
    }

    /**
     * @inheritdoc ITokenBridge
     */
    function setWhitelistedSender(address sender, bool enabled) external override onlyOwner {
        if (sender == address(0)) revert InvalidSender(sender);
        whitelistedSenders[sender] = enabled;
        if (enabled) {
            emit SenderWhitelisted(sender);
        } else {
            emit SenderRemoved(sender);
        }
    }

    /**
     * @inheritdoc ITokenBridge
     */
    function setCCIPGasLimit(uint256 gasLimit) external override onlyOwner {
        _ccipGasLimit = gasLimit;
        emit CCIPGasLimitUpdated(gasLimit);
    }

    /**
     * @inheritdoc ITokenBridge
     */
    function setAllowOutOfOrderExecution(bool allow) external override onlyOwner {
        _allowOutOfOrderExecution = allow;
        emit OutOfOrderExecutionUpdated(allow);
    }

    /**
     * @inheritdoc ITokenBridge
     */
    function pauseBridge() external override onlyOwner {
        if (_paused) revert BridgeNotPausedError();
        _paused = true;
        emit BridgePausedEvent();
    }

    /**
     * @inheritdoc ITokenBridge
     */
    function unpauseBridge() external override onlyOwner {
        if (!_paused) revert BridgePausedError();
        _paused = false;
        emit BridgeUnpausedEvent();
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @inheritdoc ITokenBridge
     */
    function isPaused() external view override returns (bool) {
        return _paused;
    }

    /**
     * @inheritdoc ITokenBridge
     */
    function getLinkBalance() external view override returns (uint256) {
        return IERC20(link).balanceOf(address(this));
    }

    /**
     * @inheritdoc ITokenBridge
     */
    function getGoldTokenBalance() external view override returns (uint256) {
        return IERC20(goldToken).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Allows the contract to receive native currency (ETH/BNB)
    /// @dev Required for receiving native token payments
    receive() external payable {}

    /**
     * @inheritdoc ITokenBridge
     */
    function withdraw(address beneficiary) external override onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert InvalidAmount(0);

        (bool sent,) = beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, beneficiary, amount);
    }

    /**
     * @inheritdoc ITokenBridge
     */
    function withdrawToken(address beneficiary, address token) external override onlyOwner {
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) revert InvalidAmount(0);

        IERC20(token).safeTransfer(beneficiary, amount);
    }
}
