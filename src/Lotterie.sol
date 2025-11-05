// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IGoldToken.sol";

/**
 * @title Lotterie
 * @dev This contract manages a lottery system where users can participate and win rewards.
 * It utilizes Chainlink VRF for randomness and Access Control for owner management.
 */
contract Lotterie is Initializable, AccessControlUpgradeable, UUPSUpgradeable, VRFConsumerBaseV2Plus {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    uint256 internal _s_subscriptionId;
    address internal _vrfCoordinator;
    bytes32 internal _s_keyHash;
    uint32 internal _callbackGasLimit;
    uint16 internal _requestConfirmations;
    uint32 internal _numWords;
    uint256 private constant ROLL_IN_PROGRESS = 42;

    IGoldToken internal _goldToken;

    uint256 internal _lastRandomDraw;
    uint256[] internal _requestIds;
    mapping(uint256 => address) internal _results;
    mapping(address => uint256) internal _gains;

    error OneRandomDrawPerMounth();

    /**
     * @dev Emitted when a random draw occurs.
     * @param requestId The ID of the request for random words.
     */
    event RandomDrawed(uint256 requestId);

    /**
     * @dev Emitted when a winner is determined.
     * @param winner The address of the winner.
     */
    event Winner(address indexed winner);

    constructor(address vrfCoordinator) VRFConsumerBaseV2Plus(vrfCoordinator) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the necessary parameters.
     * @param owner The address of the owner.
     * @param subscriptionId The subscription ID for Chainlink VRF.
     * @param vrfCoordinator The address of the VRF coordinator.
     * @param keyHash The key hash for the VRF.
     * @param callbackGasLimit The gas limit for the callback.
     * @param requestConfirmations The number of confirmations for the request.
     * @param numWords The number of random words to request.
     * @param goldToken The address of the gold token contract.
     */
    function initialize(
        address owner,
        uint256 subscriptionId,
        address vrfCoordinator,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords,
        address goldToken
    ) public initializer {
        __AccessControl_init();

        _grantRole(OWNER_ROLE, owner);
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);

        _s_subscriptionId = subscriptionId;

        _vrfCoordinator = vrfCoordinator;
        _s_keyHash = keyHash;
        _callbackGasLimit = callbackGasLimit; // 40000
        _requestConfirmations = requestConfirmations; // 3
        _numWords = numWords; // 1

        _lastRandomDraw = block.timestamp;
        _goldToken = IGoldToken(goldToken);
    }

    /**
     * @dev Authorizes the upgrade of the contract.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(OWNER_ROLE) {}

    /**
     * @dev Adds a new owner to the contract.
     * @param account The address of the new owner.
     */
    function addOwner(address account) external onlyRole(OWNER_ROLE) {
        grantRole(OWNER_ROLE, account);
    }

    /**
     * @dev Removes an owner from the contract.
     * @param account The address of the owner to be removed.
     */
    function removeOwner(address account) external onlyRole(OWNER_ROLE) {
        revokeRole(OWNER_ROLE, account);
    }

    /**
     * @dev Initiates a random draw for the lottery.
     * @return requestId The ID of the request for random words.
     * @notice Can only be called by an account with the OWNER_ROLE.
     */
    function randomDraw() external onlyRole(OWNER_ROLE) returns (uint256 requestId) {
        // One randomdraw per mounth
        require(_lastRandomDraw + 30 days <= block.timestamp, OneRandomDrawPerMounth());

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: _s_keyHash,
                subId: _s_subscriptionId,
                requestConfirmations: _requestConfirmations,
                callbackGasLimit: _callbackGasLimit,
                numWords: _numWords,
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );

        _lastRandomDraw = block.timestamp;
        _requestIds.push(requestId);
        emit RandomDrawed(requestId);
    }

    /**
     * @dev Callback function that is called by Chainlink VRF with the random words.
     * @param requestId The ID of the request for random words.
     * @param randomWords The array of random words returned by Chainlink VRF.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        // transform the result to a number between 0 and number of participants
        address[] memory users = _goldToken.getUsers();
        uint256 index = (randomWords[0] % users.length);

        // store the result
        _results[requestId] = users[index];
        _gains[users[index]] = _goldToken.balanceOf(address(this));

        // emit event
        emit Winner(users[index]);
    }

    /**
     * @dev Allows users to claim their gains from the lottery.
     * @notice Reverts if the caller has no gains to claim.
     */
    function claim() external {
        require(_gains[msg.sender] > 0, "No gain to claim");
        _gains[msg.sender] = 0;
        _goldToken.transfer(msg.sender, _gains[msg.sender]);
    }

    /**
     * @dev Checks if an account has the owner role.
     * @param account The address to check.
     * @return True if the account has the owner role, false otherwise.
     */
    function hasOwnerRole(address account) external view returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }

    /**
     * @dev Gets the last request ID for random words.
     * @return The last request ID.
     */
    function getLastRequestId() external view returns (uint256) {
        if (_requestIds.length == 0) {
            return 0;
        }
        return _requestIds[_requestIds.length - 1];
    }

    /**
     * @dev Gets the gains of a specific account.
     * @param account The address of the account.
     * @return The amount of gains for the account.
     */
    function getGains(address account) external view returns (uint256) {
        return _gains[account];
    }

    /**
     * @dev Gets the result of a specific request ID.
     * @param requestId The ID of the request.
     * @return The address of the winner for the request ID.
     */
    function getResults(uint256 requestId) external view returns (address) {
        return _results[requestId];
    }

    /**
     * @dev Gets the address of the VRF coordinator.
     * @return The address of the VRF coordinator.
     */
    function getVrfCoordinator() external view returns (address) {
        return _vrfCoordinator;
    }

    /**
     * @dev Gets the key hash used for VRF.
     * @return The key hash.
     */
    function getKeyHash() external view returns (bytes32) {
        return _s_keyHash;
    }

    /**
     * @dev Gets the callback gas limit.
     * @return The callback gas limit.
     */
    function getCallbackGasLimit() external view returns (uint32) {
        return _callbackGasLimit;
    }

    /**
     * @dev Gets the number of request confirmations.
     * @return The number of request confirmations.
     */
    function getRequestConfirmations() external view returns (uint16) {
        return _requestConfirmations;
    }

    /**
     * @dev Gets the number of words requested from VRF.
     * @return The number of words.
     */
    function getNumWords() external view returns (uint32) {
        return _numWords;
    }

    /**
     * @dev Gets the address of the gold token contract.
     * @return The address of the gold token.
     */
    function getGoldToken() external view returns (address) {
        return address(_goldToken);
    }

    /**
     * @dev Gets the subscription ID for Chainlink VRF.
     * @return The subscription ID.
     */
    function getSubscriptionId() external view returns (uint256) {
        return _s_subscriptionId;
    }

    /**
     * @dev Sets a new subscription ID for Chainlink VRF.
     * @param subscriptionId The new subscription ID.
     * @notice Can only be called by an account with the OWNER_ROLE.
     */
    function setSubscriptionId(uint256 subscriptionId) external onlyRole(OWNER_ROLE) {
        _s_subscriptionId = subscriptionId;
    }

    /**
     * @dev Sets a new VRF coordinator address.
     * @param vrfCoordinator The new VRF coordinator address.
     * @notice Can only be called by an account with the OWNER_ROLE.
     */
    function setVrfCoordinator(address vrfCoordinator) external onlyRole(OWNER_ROLE) {
        _vrfCoordinator = vrfCoordinator;
    }

    /**
     * @dev Sets a new key hash for VRF.
     * @param keyHash The new key hash.
     * @notice Can only be called by an account with the OWNER_ROLE.
     */
    function setKeyHash(bytes32 keyHash) external onlyRole(OWNER_ROLE) {
        _s_keyHash = keyHash;
    }

    /**
     * @dev Sets a new callback gas limit.
     * @param callbackGasLimit The new callback gas limit.
     * @notice Can only be called by an account with the OWNER_ROLE.
     */
    function setCallbackGasLimit(uint32 callbackGasLimit) external onlyRole(OWNER_ROLE) {
        _callbackGasLimit = callbackGasLimit;
    }

    /**
     * @dev Sets a new number of request confirmations.
     * @param requestConfirmations The new number of request confirmations.
     * @notice Can only be called by an account with the OWNER_ROLE.
     */
    function setRequestConfirmations(uint16 requestConfirmations) external onlyRole(OWNER_ROLE) {
        _requestConfirmations = requestConfirmations;
    }

    /**
     * @dev Sets a new number of words to request from VRF.
     * @param numWords The new number of words.
     * @notice Can only be called by an account with the OWNER_ROLE.
     */
    function setNumWords(uint32 numWords) external onlyRole(OWNER_ROLE) {
        _numWords = numWords;
    }

    /**
     * @dev Sets a new gold token address.
     * @param goldToken The new gold token address.
     * @notice Can only be called by an account with the OWNER_ROLE.
     */
    function setGoldToken(address goldToken) external onlyRole(OWNER_ROLE) {
        _goldToken = IGoldToken(goldToken);
    }
}
