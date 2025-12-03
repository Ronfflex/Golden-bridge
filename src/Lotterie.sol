// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IGoldToken} from "./interfaces/IGoldToken.sol";
import {ILotterie} from "./interfaces/ILotterie.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Lotterie
 * @notice Lottery system leveraging Chainlink VRF to reward GoldToken holders
 * @dev This contract manages a lottery system where users can participate and win rewards.
 * It utilizes Chainlink VRF for randomness and Access Control for owner management.
 */
contract Lotterie is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    VRFConsumerBaseV2Plus,
    ReentrancyGuard,
    ILotterie
{
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role identifier for operators allowed to manage draws and upgrades
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @notice Chainlink VRF subscription that funds randomness requests
    uint256 internal _vrfSubscriptionId;

    /// @notice Key hash identifying the VRF proving key used for draws
    bytes32 internal _vrfKeyHash;

    /// @notice Whether the payment in native tokens is enabled for the VRF subscription
    bool internal _vrfNativePayment;

    /// @notice Gas limit allocated to `fulfillRandomWords`
    uint32 internal _callbackGasLimit;

    /// @notice Number of block confirmations required before a VRF response is accepted
    uint16 internal _requestConfirmations;

    /// @notice Amount of random words requested per draw
    uint32 internal _numWords;

    /// @notice randomDrawCooldown amount of time required between draws
    uint256 internal _randomDrawCooldown;

    /// @notice Timestamp of the most recent draw, used to enforce the cooldown period
    uint256 internal _lastRandomDraw;

    /// @notice GoldToken proxy feeding participant balances and payouts
    IGoldToken internal _goldToken;

    /// @notice Historical record of VRF request identifiers
    uint256[] internal _requestIds;

    /// @notice Stores winning addresses per VRF request
    /// @dev Maps requestId => winner address
    mapping(uint256 requestId => address winner) internal _results;

    /// @notice Tracks unclaimed lottery rewards for each participant
    /// @dev Maps account => GLD amount that can be claimed
    mapping(address account => uint256 pendingGain) internal _gains;

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Locks the implementation contract
    constructor(address vrfCoordinator) VRFConsumerBaseV2Plus(vrfCoordinator) {
        _disableInitializers();
    }

    /// @inheritdoc ILotterie
    function initialize(
        address owner,
        uint256 vrfSubscriptionId,
        address vrfCoordinator,
        bool vrfNativePayment,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords,
        uint256 randomDrawCooldown,
        address goldToken
    ) external override initializer {
        __AccessControl_init();

        _grantRole(OWNER_ROLE, owner);

        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);

        _vrfSubscriptionId = vrfSubscriptionId;
        s_vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator);
        _vrfKeyHash = keyHash;
        _vrfNativePayment = vrfNativePayment;
        _callbackGasLimit = callbackGasLimit;
        _requestConfirmations = requestConfirmations;
        _numWords = numWords;
        _randomDrawCooldown = randomDrawCooldown;
        _lastRandomDraw = block.timestamp - 1 days;
        _goldToken = IGoldToken(goldToken);

        emit LotterieInitialized(
            owner,
            vrfCoordinator,
            goldToken,
            vrfSubscriptionId,
            vrfNativePayment,
            keyHash,
            callbackGasLimit,
            requestConfirmations,
            numWords,
            randomDrawCooldown
        );
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(OWNER_ROLE) {}

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILotterie
    function addOwner(address account) external override onlyRole(OWNER_ROLE) {
        grantRole(OWNER_ROLE, account);
    }

    /// @inheritdoc ILotterie
    function removeOwner(address account) external override onlyRole(OWNER_ROLE) {
        revokeRole(OWNER_ROLE, account);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILotterie
    function setVrfSubscriptionId(uint256 vrfSubscriptionId) external override onlyRole(OWNER_ROLE) {
        uint256 previous = _vrfSubscriptionId;
        _vrfSubscriptionId = vrfSubscriptionId;
        emit VrfSubscriptionUpdated(previous, vrfSubscriptionId);
    }

    /// @inheritdoc ILotterie
    function setVrfCoordinator(address vrfCoordinator) external override onlyRole(OWNER_ROLE) {
        address previous = address(s_vrfCoordinator);
        s_vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator);
        emit VrfCoordinatorUpdated(previous, vrfCoordinator);
    }

    /// @inheritdoc ILotterie
    function setKeyHash(bytes32 keyHash) external override onlyRole(OWNER_ROLE) {
        bytes32 previous = _vrfKeyHash;
        _vrfKeyHash = keyHash;
        emit KeyHashUpdated(previous, keyHash);
    }

    /// @inheritdoc ILotterie
    function setCallbackGasLimit(uint32 callbackGasLimit) external override onlyRole(OWNER_ROLE) {
        uint32 previous = _callbackGasLimit;
        _callbackGasLimit = callbackGasLimit;
        emit CallbackGasLimitUpdated(previous, callbackGasLimit);
    }

    /// @inheritdoc ILotterie
    function setRequestConfirmations(uint16 requestConfirmations) external override onlyRole(OWNER_ROLE) {
        uint16 previous = _requestConfirmations;
        _requestConfirmations = requestConfirmations;
        emit RequestConfirmationsUpdated(previous, requestConfirmations);
    }

    /// @inheritdoc ILotterie
    function setNumWords(uint32 numWords) external override onlyRole(OWNER_ROLE) {
        uint32 previous = _numWords;
        _numWords = numWords;
        emit NumWordsUpdated(previous, numWords);
    }

    /// @inheritdoc ILotterie
    function setGoldToken(address goldToken) external override onlyRole(OWNER_ROLE) {
        address previous = address(_goldToken);
        _goldToken = IGoldToken(goldToken);
        emit GoldTokenUpdated(previous, goldToken);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILotterie
    function randomDraw() external override onlyRole(OWNER_ROLE) returns (uint256) {
        if (_lastRandomDraw + _randomDrawCooldown > block.timestamp) {
            revert DrawCooldownNotExpired(_lastRandomDraw, _randomDrawCooldown, block.timestamp);
        }

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: _vrfKeyHash,
                subId: _vrfSubscriptionId,
                requestConfirmations: _requestConfirmations,
                callbackGasLimit: _callbackGasLimit,
                numWords: _numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: _vrfNativePayment}))
            })
        );

        _lastRandomDraw = block.timestamp;
        _requestIds.push(requestId);
        emit RandomDrawed(requestId);
        return requestId;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        // transform the result to a number between 0 and number of participants
        address[] memory users = _goldToken.getUsers();
        uint256 index = (randomWords[0] % users.length);

        _results[requestId] = users[index];
        _gains[users[index]] = _goldToken.balanceOf(address(this));

        emit Winner(users[index]);
    }

    /// @inheritdoc ILotterie
    function claim() external override nonReentrant {
        uint256 amount = _gains[msg.sender];
        if (amount == 0) {
            revert NoGainToClaim();
        }
        _gains[msg.sender] = 0;
        bool success = _goldToken.transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed();
        }
        emit GainClaimed(msg.sender, amount);
    }

    /// @inheritdoc ILotterie
    function hasOwnerRole(address account) external view override returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }

    /// @inheritdoc ILotterie
    function getLastRequestId() external view override returns (uint256) {
        if (_requestIds.length == 0) {
            return 0;
        }
        return _requestIds[_requestIds.length - 1];
    }

    /// @inheritdoc ILotterie
    function getGains(address account) external view override returns (uint256) {
        return _gains[account];
    }

    /// @inheritdoc ILotterie
    function getResults(uint256 requestId) external view override returns (address) {
        return _results[requestId];
    }

    /// @inheritdoc ILotterie
    function getVrfCoordinator() external view override returns (address) {
        return address(s_vrfCoordinator);
    }

    /// @inheritdoc ILotterie
    function getKeyHash() external view override returns (bytes32) {
        return _vrfKeyHash;
    }

    /// @inheritdoc ILotterie
    function getCallbackGasLimit() external view override returns (uint32) {
        return _callbackGasLimit;
    }

    /// @inheritdoc ILotterie
    function getRequestConfirmations() external view override returns (uint16) {
        return _requestConfirmations;
    }

    /// @inheritdoc ILotterie
    function getNumWords() external view override returns (uint32) {
        return _numWords;
    }

    /// @inheritdoc ILotterie
    function getGoldToken() external view override returns (address) {
        return address(_goldToken);
    }

    /// @inheritdoc ILotterie
    function getVrfSubscriptionId() external view override returns (uint256) {
        return _vrfSubscriptionId;
    }
}
