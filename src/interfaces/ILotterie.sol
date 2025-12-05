// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Lotterie Interface
 * @notice Describes the external API for the GoldToken lottery module powered by Chainlink VRF
 * @dev Consumed by GoldToken, deployment scripts, and monitoring infrastructure
 */
interface ILotterie {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configuration struct used during Lotterie initialization
     * @param owner Address granted OWNER_ROLE
     * @param vrfSubscriptionId Subscription id funding VRF requests
     * @param vrfCoordinator Address of the VRF coordinator
     * @param keyHash Chainlink VRF key hash used for randomness
     * @param callbackGasLimit Gas limit allocated for fulfillRandomWords
     * @param requestConfirmations Number of confirmations required for VRF responses
     * @param numWords Number of random words requested per draw
     * @param randomDrawCooldown Minimum time between draws
     * @param goldToken Address of the GoldToken proxy
     */
    struct LotterieConfig {
        address owner;
        uint256 vrfSubscriptionId;
        address vrfCoordinator;
        bytes32 keyHash;
        uint32 callbackGasLimit;
        uint16 requestConfirmations;
        uint32 numWords;
        uint256 randomDrawCooldown;
        address goldToken;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted whenever a VRF request for randomness is sent
     * @param requestId Unique identifier for the Chainlink VRF request
     */
    event RandomDrawed(uint256 indexed requestId);

    /**
     * @notice Emitted when a winner is determined for the active lottery
     * @param winner Address receiving the lottery gains
     */
    event Winner(address indexed winner);

    /**
     * @notice Emitted once when the Lotterie proxy is initialized
     * @param owner Address granted OWNER_ROLE
     * @param vrfCoordinator Chainlink VRF coordinator contract address
     * @param goldToken GoldToken proxy associated with the lottery
     * @param vrfSubscriptionId VRF subscription identifier configured for draws
     * @param keyHash Chainlink VRF key hash used to request randomness
     * @param callbackGasLimit Gas limit allocated to fulfillRandomWords
     * @param requestConfirmations Number of confirmations required per VRF request
     * @param numWords Number of random words requested per draw
     * @param randomDrawCooldown Minimum time required between lottery draws
     */
    event LotterieInitialized(
        address indexed owner,
        address indexed vrfCoordinator,
        address indexed goldToken,
        uint256 vrfSubscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords,
        uint256 randomDrawCooldown
    );

    /**
     * @notice Emitted when the VRF subscription id changes
     * @param previousSubscriptionId Subscription id before the update
     * @param newSubscriptionId Subscription id after the update
     */
    event VrfSubscriptionUpdated(uint256 indexed previousSubscriptionId, uint256 indexed newSubscriptionId);

    /**
     * @notice Emitted when the VRF coordinator reference changes
     * @param previousCoordinator Coordinator address before the update
     * @param newCoordinator Coordinator address after the update
     */
    event VrfCoordinatorUpdated(address indexed previousCoordinator, address indexed newCoordinator);

    /**
     * @notice Emitted when the VRF key hash changes
     * @param previousKeyHash Key hash before the update
     * @param newKeyHash Key hash after the update
     */
    event KeyHashUpdated(bytes32 indexed previousKeyHash, bytes32 indexed newKeyHash);

    /**
     * @notice Emitted when the VRF callback gas limit changes
     * @param previousGasLimit Gas limit before the update
     * @param newGasLimit Gas limit after the update
     */
    event CallbackGasLimitUpdated(uint32 indexed previousGasLimit, uint32 indexed newGasLimit);

    /**
     * @notice Emitted when the VRF confirmation requirement changes
     * @param previousConfirmations Confirmation count before the update
     * @param newConfirmations Confirmation count after the update
     */
    event RequestConfirmationsUpdated(uint16 indexed previousConfirmations, uint16 indexed newConfirmations);

    /**
     * @notice Emitted when the number of random words per draw changes
     * @param previousNumWords Word count before the update
     * @param newNumWords Word count after the update
     */
    event NumWordsUpdated(uint32 indexed previousNumWords, uint32 indexed newNumWords);

    /**
     * @notice Emitted when the GoldToken proxy linked to the lottery changes
     * @param previousGoldToken GoldToken address before the update
     * @param newGoldToken GoldToken address after the update
     */
    event GoldTokenUpdated(address indexed previousGoldToken, address indexed newGoldToken);

    /**
     * @notice Emitted when the random draw cooldown changes
     * @param previousCooldown Cooldown before the update
     * @param newCooldown Cooldown after the update
     */
    event RandomDrawCooldownUpdated(uint256 indexed previousCooldown, uint256 indexed newCooldown);

    /**
     * @notice Emitted when a participant successfully claims lottery gains
     * @param account Winner address claiming their gains
     * @param amount Amount of GLD transferred to the winner
     */
    event GainClaimed(address indexed account, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reverts when attempting to draw more than once within the cooldown period
     * @param lastDraw Timestamp of the last draw
     * @param cooldown Minimum time between draws
     * @param currentTime Current block timestamp
     */
    error DrawCooldownNotExpired(uint256 lastDraw, uint256 cooldown, uint256 currentTime);

    /// @notice Reverts when a user tries to claim gains but has none
    error NoGainToClaim();

    /// @notice Reverts when the GoldToken transfer fails during a claim
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Grants OWNER_ROLE to a new account
    /// @param account Address receiving OWNER_ROLE
    function addOwner(address account) external;

    /// @notice Revokes OWNER_ROLE from an account
    /// @param account Address losing OWNER_ROLE
    function removeOwner(address account) external;

    /**
     * @notice Updates the Chainlink VRF subscription identifier
     * @param vrfSubscriptionId New subscription id
     */
    function setVrfSubscriptionId(uint256 vrfSubscriptionId) external;

    /**
     * @notice Updates the VRF coordinator contract reference
     * @param vrfCoordinator Address of the VRF coordinator contract
     */
    function setVrfCoordinator(address vrfCoordinator) external;

    /**
     * @notice Updates the VRF key hash used for randomness requests
     * @param keyHash New VRF key hash
     */
    function setKeyHash(bytes32 keyHash) external;

    /**
     * @notice Adjusts the gas limit used for the VRF callback
     * @param callbackGasLimit New callback gas limit
     */
    function setCallbackGasLimit(uint32 callbackGasLimit) external;

    /**
     * @notice Adjusts the number of confirmations required for VRF requests
     * @param requestConfirmations New confirmation count
     */
    function setRequestConfirmations(uint16 requestConfirmations) external;

    /**
     * @notice Adjusts the number of random words requested from VRF
     * @param numWords New number of random words per request
     */
    function setNumWords(uint32 numWords) external;

    /**
     * @notice Updates the GoldToken implementation used to read balances and manage gains
     * @param goldToken Address of the GoldToken proxy
     */
    function setGoldToken(address goldToken) external;

    /**
     * @notice Updates the minimum time required between lottery draws
     * @param randomDrawCooldown New cooldown period
     */
    function setRandomDrawCooldown(uint256 randomDrawCooldown) external;

    /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the proxy with VRF configuration and GoldToken reference
    function initialize(LotterieConfig calldata config) external;

    /**
     * @notice Requests randomness from Chainlink to pick a lottery winner
     * @param enableNativePayment When true, the VRF request will be paid in native tokens otherwise LINK will be used
     * @return requestId Identifier of the VRF request
     */
    function randomDraw(bool enableNativePayment) external returns (uint256 requestId);

    /// @notice Claims accrued lottery gains for the caller
    function claim() external;

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Checks whether an account currently holds OWNER_ROLE
    /// @param account Address to inspect
    /// @return True when the account has OWNER_ROLE
    function hasOwnerRole(address account) external view returns (bool);

    /// @notice Returns the most recent VRF request identifier
    /// @return requestId Last stored VRF request id (zero when no draws)

    function getLastRequestId() external view returns (uint256);
    /**
     * @notice Returns the pending gains assigned to an account
     * @param account Address to inspect
     * @return Amount of GLD available to claim
     */
    function getGains(address account) external view returns (uint256);

    /**
     * @notice Returns the winner associated with a specific VRF request id
     * @param requestId VRF request identifier
     * @return Winner address linked to the request
     */
    function getResults(uint256 requestId) external view returns (address);

    /**
     * @notice Returns the VRF coordinator in use
     * @return Address of the VRF coordinator contract
     */
    function getVrfCoordinator() external view returns (address);

    /**
     * @notice Returns the VRF key hash currently configured
     * @return VRF key hash value
     */
    function getKeyHash() external view returns (bytes32);

    /**
     * @notice Returns the gas limit used for VRF callbacks
     * @return Callback gas limit
     */
    function getCallbackGasLimit() external view returns (uint32);

    /**
     * @notice Returns the number of confirmations before VRF fulfills requests
     * @return Confirmation count
     */
    function getRequestConfirmations() external view returns (uint16);

    /**
     * @notice Returns the number of random words requested per draw
     * @return Number of random words
     */
    function getNumWords() external view returns (uint32);

    /**
     * @notice Returns the GoldToken proxy address used by the lottery
     * @return GoldToken address
     */
    function getGoldToken() external view returns (address);

    /**
     * @notice Returns the VRF subscription identifier currently configured
     * @return Subscription id
     */
    function getVrfSubscriptionId() external view returns (uint256);

    /**
     * @notice Returns the minimum time required between lottery draws
     * @return Cooldown period
     */
    function getRandomDrawCooldown() external view returns (uint256);
}
