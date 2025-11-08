// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Lotterie Interface
 * @notice Describes the external API for the GoldToken lottery module powered by Chainlink VRF
 * @dev Consumed by GoldToken, deployment scripts, and monitoring infrastructure
 */
interface ILotterie {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Emitted whenever a VRF request for randomness is sent
     * @param requestId Unique identifier for the Chainlink VRF request
     */
    event RandomDrawed(uint256 requestId);
    /**
     * @notice Emitted when a winner is determined for the active lottery
     * @param winner Address receiving the lottery gains
     */
    event Winner(address indexed winner);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @notice Reverts when attempting to draw more than once within a rolling 24-hour window
    error OneRandomDrawPerDay();
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

    /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the proxy with VRF configuration and GoldToken reference
     * @param owner Address granted OWNER_ROLE
     * @param vrfSubscriptionId Subscription id funding VRF requests
     * @param vrfCoordinator Address of the VRF coordinator
     * @param keyHash Chainlink VRF key hash used for randomness
     * @param callbackGasLimit Gas limit allocated for fulfillRandomWords
     * @param requestConfirmations Number of confirmations required for VRF responses
     * @param numWords Number of random words requested per draw
     * @param goldToken Address of the GoldToken proxy
     */
    function initialize(
        address owner,
        uint256 vrfSubscriptionId,
        address vrfCoordinator,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords,
        address goldToken
    ) external;

    /**
     * @notice Requests randomness from Chainlink to pick a lottery winner
     * @return requestId Identifier of the VRF request
     */
    function randomDraw() external returns (uint256 requestId);
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
}
