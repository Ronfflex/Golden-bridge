// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ITokenBridge
 * @notice Interface for the cross-chain TokenBridge contract that enables bridging of GoldTokens
 * @dev Defines all external functions and events for the TokenBridge implementation
 */
interface ITokenBridge {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Emitted when tokens are bridged to another chain
     * @param messageId Unique identifier for the bridge transaction
     * @param sender Address initiating the bridge transaction
     * @param receiver Address receiving the tokens on the destination chain
     * @param amount Amount of tokens being bridged
     * @param destinationChainSelector Identifier of the destination chain
     * @param feeToken Token used to pay the bridging fees (LINK or native token)
     * @param fees Amount of fees paid for the bridge transaction
     */
    event TokensBridged(
        bytes32 indexed messageId,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        uint64 destinationChainSelector,
        address feeToken,
        uint256 fees
    );

    /**
     * @notice Emitted when tokens are received from another chain
     * @param messageId Unique identifier for the bridge transaction
     * @param receiver Address receiving the tokens
     * @param amount Amount of tokens received
     * @param sourceChainSelector Identifier of the source chain
     */
    event TokensReceived(
        bytes32 indexed messageId, address indexed receiver, uint256 amount, uint64 sourceChainSelector
    );

    /**
     * @notice Emitted when a chain is added to the whitelist
     * @param chainSelector Identifier of the whitelisted chain
     */
    event ChainWhitelisted(uint64 chainSelector);

    /**
     * @notice Emitted when a chain is removed from the whitelist
     * @param chainSelector Identifier of the removed chain
     */
    event ChainRemoved(uint64 chainSelector);

    /**
     * @notice Emitted when a sender is added to the whitelist
     * @param sender Address of the whitelisted sender
     */
    event SenderWhitelisted(address sender);

    /**
     * @notice Emitted when a sender is removed from the whitelist
     * @param sender Address of the removed sender
     */
    event SenderRemoved(address sender);

    /**
     * @notice Emitted when the CCIP gas limit is updated
     * @param newGasLimit New gas limit for CCIP operations
     */
    event CCIPGasLimitUpdated(uint256 newGasLimit);

    /**
     * @notice Emitted when the out-of-order execution setting is updated
     * @param allowed Whether out-of-order execution is allowed
     */
    event OutOfOrderExecutionUpdated(bool allowed);

    /**
     * @notice Emitted when the bridge is paused
     */
    event BridgePausedEvent();

    /**
     * @notice Emitted when the bridge is unpaused
     */
    event BridgeUnpausedEvent();

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Thrown when there are insufficient tokens to pay for fees
     * @param currentBalance Current balance available
     * @param calculatedFees Required fee amount
     */
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);

    /**
     * @notice Thrown when attempting to process a message that has already been processed
     * @param messageId ID of the message that was already processed
     */
    error MessageAlreadyProcessed(bytes32 messageId);

    /**
     * @notice Thrown when receiving a message from an invalid chain
     * @param sourceChainSelector Identifier of the invalid chain
     */
    error InvalidSourceChain(uint64 sourceChainSelector);

    /**
     * @notice Thrown when an invalid sender address is used
     * @param sender The invalid sender address
     */
    error InvalidSender(address sender);

    /**
     * @notice Thrown when an invalid amount is specified
     * @param amount The invalid amount
     */
    error InvalidAmount(uint256 amount);

    /**
     * @notice Thrown when there are insufficient tokens for a transfer
     * @param token The token address
     * @param required The required amount
     * @param balance The current balance
     */
    error InsufficientBalance(address token, uint256 required, uint256 balance);

    /**
     * @notice Thrown when attempting to use a non-whitelisted chain
     * @param chainSelector The non-whitelisted chain's identifier
     */
    error ChainNotWhitelisted(uint64 chainSelector);

    /**
     * @notice Thrown when receiving a message from a non-whitelisted sender
     * @param sender The non-whitelisted sender address
     */
    error SenderNotWhitelisted(address sender);

    /**
     * @notice Thrown when attempting to perform operations while bridge is paused
     */
    error BridgePausedError();

    /**
     * @notice Thrown when attempting to pause an already paused bridge
     */
    error BridgeNotPausedError();

    /**
     * @notice Thrown when a withdrawal operation fails
     * @param owner The owner who initiated the withdrawal
     * @param target The intended recipient
     * @param value The amount that failed to withdraw
     */
    error FailedToWithdrawEth(address owner, address target, uint256 value);

    /*//////////////////////////////////////////////////////////////
                            BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Bridges tokens using LINK for fee payment
     * @param receiver Address that will receive tokens on destination chain
     * @param amount Amount of tokens to bridge
     * @return messageId Unique identifier for the bridge transaction
     */
    function bridgeTokensPayLink(address receiver, uint256 amount) external returns (bytes32 messageId);

    /**
     * @notice Bridges tokens using native currency for fee payment
     * @param receiver Address that will receive tokens on destination chain
     * @param amount Amount of tokens to bridge
     * @return messageId Unique identifier for the bridge transaction
     */
    function bridgeTokensPayNative(address receiver, uint256 amount) external payable returns (bytes32 messageId);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Updates the whitelist status of a chain
     * @param chainSelector The chain selector to update
     * @param enabled Whether to enable or disable the chain
     */
    function setWhitelistedChain(uint64 chainSelector, bool enabled) external;

    /**
     * @notice Updates the whitelist status of a sender
     * @param sender The sender address to update
     * @param enabled Whether to enable or disable the sender
     */
    function setWhitelistedSender(address sender, bool enabled) external;

    /**
     * @notice Updates the gas limit for CCIP operations
     * @param gasLimit New gas limit to set
     */
    function setCCIPGasLimit(uint256 gasLimit) external;

    /**
     * @notice Updates the out-of-order execution setting
     * @param allow Whether to allow out-of-order execution
     */
    function setAllowOutOfOrderExecution(bool allow) external;

    /**
     * @notice Pauses the bridge
     */
    function pauseBridge() external;

    /**
     * @notice Unpauses the bridge
     */
    function unpauseBridge() external;

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Checks if the bridge is paused
     * @return bool True if the bridge is paused
     */
    function isPaused() external view returns (bool);

    /**
     * @notice Gets the contract's LINK token balance
     * @return uint256 The amount of LINK tokens held by the contract
     */
    function getLinkBalance() external view returns (uint256);

    /**
     * @notice Gets the contract's GoldToken balance
     * @return uint256 The amount of GoldTokens held by the contract
     */
    function getGoldTokenBalance() external view returns (uint256);

    /**
     * @notice Gets the destination chain selector
     * @return uint64 The chain selector for the destination chain
     */
    function destinationChainSelector() external view returns (uint64);

    /**
     * @notice Gets the GoldToken contract address
     * @return address The address of the GoldToken contract
     */
    function goldToken() external view returns (address);

    /**
     * @notice Gets the LINK token contract address
     * @return address The address of the LINK token contract
     */
    function link() external view returns (address);

    /**
     * @notice Checks if a message has been processed
     * @param messageId The ID of the message to check
     * @return bool True if the message has been processed
     */
    function processedMessages(bytes32 messageId) external view returns (bool);

    /**
     * @notice Checks if a chain is whitelisted
     * @param chainSelector The chain selector to check
     * @return bool True if the chain is whitelisted
     */
    function whitelistedChains(uint64 chainSelector) external view returns (bool);

    /**
     * @notice Checks if a sender is whitelisted
     * @param sender The sender address to check
     * @return bool True if the sender is whitelisted
     */
    function whitelistedSenders(address sender) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                          WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Withdraws all native currency from the contract
     * @param beneficiary Address to receive the withdrawn currency
     */
    function withdraw(address beneficiary) external;

    /**
     * @notice Withdraws all tokens of a specific type from the contract
     * @param beneficiary Address to receive the withdrawn tokens
     * @param token Token contract address to withdraw
     */
    function withdrawToken(address beneficiary, address token) external;
}
