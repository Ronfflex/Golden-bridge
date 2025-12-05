// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Gold Token Interface
 * @notice Describes the external API of the upgradeable GoldToken ERC-20 implementation
 * @dev Used by Lotterie, TokenBridge, and deployment scripts to interact with the token proxy
 */
interface IGoldToken {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted once during proxy initialization to capture deployment context
     * @param owner Address granted OWNER_ROLE and set as initial fee recipient
     * @param dataFeedGold Chainlink feed used for gold pricing
     * @param dataFeedEth Chainlink feed used for ETH/USD pricing
     */
    event GoldTokenInitialized(address indexed owner, address indexed dataFeedGold, address indexed dataFeedEth);

    /**
     * @notice Emitted whenever protocol fees are minted from an ETH deposit
     * @param to Recipient receiving the freshly minted GLD
     * @param amount Amount of GLD minted (net of protocol fees)
     */
    event Mint(address indexed to, uint256 amount);

    /**
     * @notice Emitted when the fee recipient address changes
     * @param previousFeesAddress Fee recipient before the update
     * @param newFeesAddress Fee recipient after the update
     */
    event FeesAddressUpdated(address indexed previousFeesAddress, address indexed newFeesAddress);

    /**
     * @notice Emitted when the linked Lotterie contract is updated
     * @param previousLotterieAddress Lotterie address before the change
     * @param newLotterieAddress Lotterie address after the change
     */
    event LotterieAddressUpdated(address indexed previousLotterieAddress, address indexed newLotterieAddress);

    /**
     * @notice Emitted when an address becomes lottery-eligible for the first time
     * @param user Account added to the eligibility list
     * @param timestamp Block timestamp recorded for the user
     */
    event UserAdded(address indexed user, uint256 timestamp);

    /**
     * @notice Emitted when an address is removed from the lottery-eligible set
     * @param user Account removed from tracking
     */
    event UserRemoved(address indexed user);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a function expecting a positive ETH value receives zero
    error ValueMustBeGreaterThanZero();

    /// @notice Thrown when a mint, burn, or transfer amount is zero
    error AmountMustBeGreaterThanZero();

    /// @notice Thrown when Chainlink feeds yield a non-positive gold price in ETH
    error InvalidGoldPrice();

    /// @notice Thrown when withdrawing ETH to an owner fails
    error EthTransferFailed();

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Grants OWNER_ROLE to a new account
     * @param account Address receiving OWNER_ROLE
     */
    function addOwner(address account) external;

    /**
     * @notice Revokes OWNER_ROLE from an account
     * @param account Address losing OWNER_ROLE
     */
    function removeOwner(address account) external;

    /// @notice Pauses minting and burning operations
    function pause() external;

    /// @notice Resumes minting and burning operations
    function unpause() external;

    /**
     * @notice Updates the recipient of protocol fees
     * @param feesAddress Address receiving fees minted during token operations
     */
    function setFeesAddress(address feesAddress) external;

    /**
     * @notice Sets the Lotterie contract address used for fee distribution and user tracking
     * @param lotterieAddress Address of the Lotterie contract
     */
    function setLotterieAddress(address lotterieAddress) external;

    /// @notice Withdraws the entire ETH balance accumulated in the token contract
    function claimEth() external;

    /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the proxy with owner credentials and Chainlink price feeds
     * @param owner Address granted OWNER_ROLE and initial fee recipient
     * @param dataFeedGoldAddress Chainlink aggregator returning the gold price per troy ounce
     * @param dataFeedEthAddress Chainlink aggregator returning the ETH/USD price
     */
    function initialize(address owner, address dataFeedGoldAddress, address dataFeedEthAddress) external;

    /// @notice Converts supplied ETH into GLD using Chainlink prices and mints tokens
    function mint() external payable;

    /**
     * @notice Burns GLD from the caller and updates lottery eligibility bookkeeping
     * @param amount Amount of GLD to burn
     */
    function burn(uint256 amount) external;

    /**
     * @notice Transfers GLD while keeping user eligibility data in sync
     * @param to Recipient address
     * @param amount Amount of GLD to transfer
     * @return True when the transfer succeeds
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the protocol fee percentage expressed in whole percents
     * @return Protocol fee percentage applied to mint/burn amounts
     */
    function getFees() external view returns (uint256);

    /**
     * @notice Returns the address receiving protocol fees
     * @return Fee recipient address
     */
    function getFeesAddress() external view returns (address);

    /**
     * @notice Returns the list of lottery-eligible users tracked by GoldToken
     * @return Array of user addresses
     */
    function getUsers() external view returns (address[] memory);

    /**
     * @notice Returns the user at a specific index in the tracked users array
     * @param index Index of the user to retrieve
     * @return User address at the specified index
     */
    function getUserByIndex(uint256 index) external view returns (address);

    /**
     * @notice Returns the total number of tracked users
     * @return Total count of users
     */
    function getUserCount() external view returns (uint256);

    /**
     * @notice Returns users alongside their latest eligibility timestamps
     * @return users Array of tracked addresses
     * @return timestamps Array of UNIX timestamps matching the users array
     */
    function getTimestamps() external view returns (address[] memory, uint256[] memory);

    /**
     * @notice Checks whether an account owns OWNER_ROLE
     * @param account Address to inspect
     * @return True if OWNER_ROLE is assigned to the account
     */
    function hasOwnerRole(address account) external view returns (bool);

    /**
     * @notice Returns the Chainlink-derived gold price expressed in ETH with 18 decimals
     * @return Gold price in ETH scaled by 1e18
     */
    function getGoldPriceInEth() external view returns (int256);

    /**
     * @notice Returns the GLD balance of an account
     * @param account Address to query
     * @return GLD balance for the provided account
     */
    function balanceOf(address account) external view returns (uint256);
}
