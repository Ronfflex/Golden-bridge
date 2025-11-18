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
    uint256 private constant ROLL_IN_PROGRESS = 42;

    uint256 internal _vrfSubscriptionId;
    bytes32 internal _vrfKeyHash;
    uint32 internal _callbackGasLimit;
    uint16 internal _requestConfirmations;
    uint32 internal _numWords;

    IGoldToken internal _goldToken;

    uint256 internal _lastRandomDraw;
    uint256[] internal _requestIds;
    mapping(uint256 => address) internal _results;
    mapping(address => uint256) internal _gains;

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
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords,
        address goldToken
    ) external override initializer {
        __AccessControl_init();

        _grantRole(OWNER_ROLE, owner);

        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);

        _vrfSubscriptionId = vrfSubscriptionId;
        s_vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator);
        _vrfKeyHash = keyHash;
        _callbackGasLimit = callbackGasLimit; // 40000
        _requestConfirmations = requestConfirmations; // 3
        _numWords = numWords; // 1

        _lastRandomDraw = block.timestamp - 1 days;
        _goldToken = IGoldToken(goldToken);
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
        _vrfSubscriptionId = vrfSubscriptionId;
    }

    /// @inheritdoc ILotterie
    function setVrfCoordinator(address vrfCoordinator) external override onlyRole(OWNER_ROLE) {
        s_vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator);
    }

    /// @inheritdoc ILotterie
    function setKeyHash(bytes32 keyHash) external override onlyRole(OWNER_ROLE) {
        _vrfKeyHash = keyHash;
    }

    /// @inheritdoc ILotterie
    function setCallbackGasLimit(uint32 callbackGasLimit) external override onlyRole(OWNER_ROLE) {
        _callbackGasLimit = callbackGasLimit;
    }

    /// @inheritdoc ILotterie
    function setRequestConfirmations(uint16 requestConfirmations) external override onlyRole(OWNER_ROLE) {
        _requestConfirmations = requestConfirmations;
    }

    /// @inheritdoc ILotterie
    function setNumWords(uint32 numWords) external override onlyRole(OWNER_ROLE) {
        _numWords = numWords;
    }

    /// @inheritdoc ILotterie
    function setGoldToken(address goldToken) external override onlyRole(OWNER_ROLE) {
        _goldToken = IGoldToken(goldToken);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILotterie
    function randomDraw() external override onlyRole(OWNER_ROLE) returns (uint256) {
        if (_lastRandomDraw + 1 days > block.timestamp) {
            revert OneRandomDrawPerDay();
        }

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: _vrfKeyHash,
                subId: _vrfSubscriptionId,
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
