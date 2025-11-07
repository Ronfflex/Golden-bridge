// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ILotterie
 * @notice External interface for the Lotterie contract
 */
interface ILotterie {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event RandomDrawed(uint256 requestId);
    event Winner(address indexed winner);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error OneRandomDrawPerDay();
    error NoGainToClaim();

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function addOwner(address account) external;
    function removeOwner(address account) external;
    function setVrfSubscriptionId(uint256 vrfSubscriptionId) external;
    function setVrfCoordinator(address vrfCoordinator) external;
    function setKeyHash(bytes32 keyHash) external;
    function setCallbackGasLimit(uint32 callbackGasLimit) external;
    function setRequestConfirmations(uint16 requestConfirmations) external;
    function setNumWords(uint32 numWords) external;
    function setGoldToken(address goldToken) external;

    /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
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

    function randomDraw() external returns (uint256 requestId);
    function claim() external;

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function hasOwnerRole(address account) external view returns (bool);
    function getLastRequestId() external view returns (uint256);
    function getGains(address account) external view returns (uint256);
    function getResults(uint256 requestId) external view returns (address);
    function getVrfCoordinator() external view returns (address);
    function getKeyHash() external view returns (bytes32);
    function getCallbackGasLimit() external view returns (uint32);
    function getRequestConfirmations() external view returns (uint16);
    function getNumWords() external view returns (uint32);
    function getGoldToken() external view returns (address);
    function getVrfSubscriptionId() external view returns (uint256);
}
