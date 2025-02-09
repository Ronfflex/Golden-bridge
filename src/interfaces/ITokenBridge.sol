// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ITokenBridge
 * @notice Interface for the cross-chain TokenBridge contract that enables bridging of GoldTokens
 * @dev Defines all external functions and events for the TokenBridge implementation
 */
interface ITokenBridge {
    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/
    enum PayFeesIn {
        Native,
        LINK
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event TokensBridged(
        bytes32 indexed messageId,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        uint64 destinationChainSelector,
        address feeToken,
        uint256 fees
    );

    event TokensReceived(
        bytes32 indexed messageId, address indexed receiver, uint256 amount, uint64 sourceChainSelector
    );

    event ChainWhitelisted(uint64 chainSelector);
    event ChainRemoved(uint64 chainSelector);
    event SenderWhitelisted(address sender);
    event SenderRemoved(address sender);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error MessageAlreadyProcessed(bytes32 messageId);
    error InvalidSourceChain(uint64 sourceChainSelector);
    error InvalidSender(address sender);
    error InvalidAmount(uint256 amount);
    error InvalidChainSelector(uint64 chainSelector);
    error ChainNotWhitelisted(uint64 chainSelector);
    error SenderNotWhitelisted(address sender);
    error FailedToWithdrawEth(address owner, address target, uint256 value);

    /*//////////////////////////////////////////////////////////////
                            BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function bridgeTokens(address receiver, uint256 amount, PayFeesIn payFeesIn)
        external
        payable
        returns (bytes32 messageId);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setWhitelistedChain(uint64 chainSelector, bool enabled, bytes memory ccipExtraArgs) external;

    function setWhitelistedSender(address sender, bool enabled) external;

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getLinkBalance() external view returns (uint256);
    function getGoldTokenBalance() external view returns (uint256);
    function destinationChainSelector() external view returns (uint64);
    function goldToken() external view returns (address);
    function link() external view returns (address);
    function processedMessages(bytes32 messageId) external view returns (bool);
    function whitelistedChains(uint64 chainSelector) external view returns (bool);
    function whitelistedSenders(address sender) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function withdraw(address beneficiary) external;
    function withdrawToken(address beneficiary, address token) external;
}
