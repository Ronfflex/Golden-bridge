// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IGoldToken.sol";

contract Lotterie is Initializable, AccessControlUpgradeable, UUPSUpgradeable, VRFConsumerBaseV2Plus {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    uint256 _s_subscriptionId;
    address _vrfCoordinator;
    bytes32 _s_keyHash;
    uint32 _callbackGasLimit;
    uint16 _requestConfirmations;
    uint32 _numWords;
    uint256 private constant ROLL_IN_PROGRESS = 42;

    IGoldToken _goldToken;

    uint256 _lastRandomDraw;
    uint256[] _requestIds;
    mapping(uint256 => address) _results;
    mapping(address => uint256) _gains;

    error OneRandomDrawPerMounth();

    event RandomDrawed(uint256 requestId);
    event Winner(address winner);

    constructor(address vrfCoordinator) VRFConsumerBaseV2Plus(vrfCoordinator) {
        _disableInitializers();
    }

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
        __UUPSUpgradeable_init();

        _grantRole(OWNER_ROLE, owner);
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);

        _s_subscriptionId = subscriptionId;

        _vrfCoordinator = vrfCoordinator; // 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B
        _s_keyHash = keyHash; // 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
        _callbackGasLimit = callbackGasLimit; // 40000
        _requestConfirmations = requestConfirmations; // 3
        _numWords = numWords; // 1

        _lastRandomDraw = block.timestamp;
        _goldToken = IGoldToken(goldToken);
    }

    function _authorizeUpgrade(address) internal override onlyRole(OWNER_ROLE) {}

    function addOwner(address account) external onlyRole(OWNER_ROLE) {
        grantRole(OWNER_ROLE, account);
    }

    function removeOwner(address account) external onlyRole(OWNER_ROLE) {
        revokeRole(OWNER_ROLE, account);
    }

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

    function claim() external {
        require(_gains[msg.sender] > 0, "No gain to claim");
        _gains[msg.sender] = 0;
        _goldToken.transfer(msg.sender, _gains[msg.sender]);
    }

    function hasOwnerRole(address account) external view returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }
}
