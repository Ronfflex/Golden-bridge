// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title TokenBridge Interface
 * @notice Describes the external CCIP-powered bridge used to move GLD between chains
 * @dev Surfaces all admin, core, and view functions consumed by off-chain agents and on-chain integrations
 */
interface ITokenBridge {
    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/
    /// @notice Enum describing the asset used to pay CCIP fees
    enum PayFeesIn {
        /// @notice Use the native gas token to settle CCIP fees
        Native,
        /// @notice Use LINK to settle CCIP fees
        LINK
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Emitted once the TokenBridge proxy completes initialization
     * @param owner Address granted OWNER_ROLE
     * @param link LINK token used to pay CCIP fees
     * @param goldToken GoldToken proxy managed by the bridge
     * @param destinationChainSelector Default destination selector configured for outbound messages
     */
    event TokenBridgeInitialized(
        address indexed owner, address indexed link, address indexed goldToken, uint64 destinationChainSelector
    );

    /**
     * @notice Emitted when GLD is bridged out to a destination chain
     * @param messageId CCIP message identifier
     * @param sender Address initiating the bridge transfer
     * @param receiver Account receiving the bridged GLD on the destination chain
     * @param amount Amount of GLD bridged
     * @param destinationChainSelector Chain selector identifying the destination network
     * @param feeToken Address of the token used to pay fees (zero for native)
     * @param fees Amount of fees charged for the bridge
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
     * @notice Emitted when a CCIP message is processed and GLD is released on the destination chain
     * @param messageId CCIP message identifier
     * @param receiver Account receiving the bridged GLD locally
     * @param amount Amount of GLD transferred
     * @param sourceChainSelector Chain selector of the origin network
     */
    event TokensReceived(
        bytes32 indexed messageId, address indexed receiver, uint256 amount, uint64 indexed sourceChainSelector
    );

    /**
     * @notice Emitted when a CCIP message is processed without transferring GLD
     * @param messageId CCIP message identifier
     * @param sourceChainSelector Chain selector of the origin network
     */
    event MessageProcessedWithoutToken(bytes32 indexed messageId, uint64 indexed sourceChainSelector);

    /**
     * @notice Emitted when a chain selector is whitelisted for bridging
     * @param chainSelector Chain selector that became whitelisted
     */
    event ChainWhitelisted(uint64 indexed chainSelector);
    /**
     * @notice Emitted when a chain selector is removed from the whitelist
     * @param chainSelector Chain selector that was removed
     */
    event ChainRemoved(uint64 indexed chainSelector);
    /**
     * @notice Emitted when an address is authorized to initiate bridge transfers
     * @param sender Address added to the sender whitelist
     */
    event SenderWhitelisted(address indexed sender);
    /**
     * @notice Emitted when an address is removed from the sender whitelist
     * @param sender Address removed from the sender whitelist
     */
    event SenderRemoved(address indexed sender);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Reverts when the contract balance is insufficient to cover CCIP fees
     * @param currentBalance Current balance of the fee token
     * @param calculatedFees Required fee amount
     */
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    /**
     * @notice Reverts when a CCIP message is processed more than once
     * @param messageId Identifier of the duplicate message
     */
    error MessageAlreadyProcessed(bytes32 messageId);
    /**
     * @notice Reverts when a message originates from a chain selector that is not recognized
     * @param sourceChainSelector Chain selector provided by the message
     */
    error InvalidSourceChain(uint64 sourceChainSelector);
    /**
     * @notice Reverts when a message is received from an unauthorized sender
     * @param sender Address extracted from the CCIP message
     */
    error InvalidSender(address sender);
    /**
     * @notice Reverts when attempting to bridge zero tokens
     * @param amount Amount of GLD attempted to bridge
     */
    error InvalidAmount(uint256 amount);
    /**
     * @notice Reverts when a chain selector value is outside accepted bounds
     * @param chainSelector Provided chain selector
     */
    error InvalidChainSelector(uint64 chainSelector);
    /**
     * @notice Reverts when a chain selector has not been whitelisted for bridging
     * @param chainSelector Chain selector that lacks authorization
     */
    error ChainNotWhitelisted(uint64 chainSelector);
    /**
     * @notice Reverts when a sender is not on the whitelist
     * @param sender Address attempting to bridge without authorization
     */
    error SenderNotWhitelisted(address sender);
    /**
     * @notice Reverts when a low-level ETH withdrawal fails
     * @param owner Address initiating the withdrawal
     * @param target Destination address of the ETH transfer
     * @param value Amount of ETH to transfer
     */
    error FailedToWithdrawEth(address owner, address target, uint256 value);

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the bridge with owner credentials, token references, and default destination
     * @param owner Address granted OWNER_ROLE within the implementation
     * @param _link Address of the LINK token used to pay CCIP fees
     * @param _goldToken Address of the local GoldToken proxy
     * @param _destinationChainSelector Default destination chain selector for outbound messages
     */
    function initialize(address owner, address _link, address _goldToken, uint64 _destinationChainSelector) external;

    /**
     * @notice Bridges GLD to another chain using Chainlink CCIP
     * @param receiver Address receiving GLD on the destination chain
     * @param amount Amount of GLD to bridge
     * @param payFeesIn Enum specifying whether fees are paid in native gas or LINK
     * @return messageId CCIP message identifier assigned to the bridge request
     */
    function bridgeTokens(address receiver, uint256 amount, PayFeesIn payFeesIn)
        external
        payable
        returns (bytes32 messageId);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Whitelists or removes a chain selector and configures CCIP extra arguments
     * @param chainSelector Chain selector to configure
     * @param enabled Boolean toggling whitelist state
     * @param ccipExtraArgs ABI encoded extra arguments for CCIP (gas limits, etc.)
     */
    function setWhitelistedChain(uint64 chainSelector, bool enabled, bytes memory ccipExtraArgs) external;
    /**
     * @notice Whitelists or removes an address authorized to initiate bridging
     * @param sender Address to configure
     * @param enabled Boolean toggling whitelist state
     */
    function setWhitelistedSender(address sender, bool enabled) external;

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the LINK balance held by the bridge
     * @return LINK balance of the contract
     */
    function getLinkBalance() external view returns (uint256);
    /**
     * @notice Returns the GLD balance held by the bridge
     * @return GLD balance of the contract
     */
    function getGoldTokenBalance() external view returns (uint256);
    /**
     * @notice Returns the currently configured destination chain selector
     * @return Chain selector value
     */
    function destinationChainSelector() external view returns (uint64);
    /**
     * @notice Returns the GoldToken proxy address managed by the bridge
     * @return GoldToken address
     */
    function goldToken() external view returns (address);
    /**
     * @notice Returns the LINK token address used for fees
     * @return LINK token address
     */
    function link() external view returns (address);
    /**
     * @notice Returns whether a CCIP message id has already been processed
     * @param messageId Identifier of the CCIP message
     * @return True when the message was processed
     */
    function processedMessages(bytes32 messageId) external view returns (bool);
    /**
     * @notice Returns whether a chain selector is whitelisted for bridging
     * @param chainSelector Chain selector to inspect
     * @return True when the chain selector is whitelisted
     */
    function whitelistedChains(uint64 chainSelector) external view returns (bool);
    /**
     * @notice Returns whether an address is whitelisted for initiating bridge transfers
     * @param sender Address to inspect
     * @return True when the sender is whitelisted
     */
    function whitelistedSenders(address sender) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Withdraws accumulated ETH fees to a beneficiary
     * @param beneficiary Address receiving the ETH
     */
    function withdraw(address beneficiary) external;
    /**
     * @notice Withdraws arbitrary ERC-20 tokens (including LINK) to a beneficiary
     * @param beneficiary Address receiving the tokens
     * @param token Address of the ERC-20 token to withdraw
     */
    function withdrawToken(address beneficiary, address token) external;
}
