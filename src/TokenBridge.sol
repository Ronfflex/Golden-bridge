// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {GoldToken} from "./GoldToken.sol";

/**
 * @title TokenBridge
 * @notice Cross-chain bridge implementation for GoldToken using Chainlink's CCIP
 * @dev Enables secure token transfer between Ethereum and BSC networks using Chainlink's CCIP protocol
 * @custom:security-contact security@goldbridge.com
 */
contract TokenBridge is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Chain selector for the destination chain (BSC)
    uint64 public immutable destinationChainSelector;
    /// @notice Address of the GoldToken contract
    address public immutable goldToken;
    /// @notice Address of the LINK token used for fees
    address public immutable link;

    /// @notice Mapping to track processed CCIP messages
    mapping(bytes32 => bool) public processedMessages;
    /// @notice Mapping of whitelisted chains that can interact with this contract
    mapping(uint64 => bool) public whitelistedChains;
    /// @notice Mapping of whitelisted sender addresses on other chains
    mapping(address => bool) public whitelistedSenders;

    /// @notice Gas limit for cross-chain operations
    uint256 private _ccipGasLimit;
    /// @notice Flag to allow out-of-order message execution
    bool private _allowOutOfOrderExecution;
    /// @notice Flag indicating if the bridge is paused
    bool private _paused;

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
    event BridgePaused();
    event BridgeUnpaused();
    event CCIPGasLimitUpdated(uint256 newGasLimit);
    event OutOfOrderExecutionUpdated(bool allowed);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error MessageAlreadyProcessed(bytes32 messageId);
    error InvalidSourceChain(uint64 sourceChainSelector);
    error InvalidSender(address sender);
    error InvalidAmount(uint256 amount);
    error InsufficientBalance(address token, uint256 required, uint256 balance);
    error ChainNotWhitelisted(uint64 chainSelector);
    error SenderNotWhitelisted(address sender);
    error BridgePaused();
    error BridgeNotPaused();
    error FailedToWithdrawEth(address owner, address target, uint256 value);

    /**
     * @notice Initializes the bridge contract
     * @dev Sets up initial configuration including whitelisting the destination chain
     * @param _router The address of the CCIP router contract
     * @param _link The address of the LINK token contract
     * @param _goldToken The address of the GoldToken contract
     * @param _destinationChainSelector The chain selector for the destination chain (BSC)
     */
    constructor(address _router, address _link, address _goldToken, uint64 _destinationChainSelector)
        CCIPReceiver(_router)
    {
        if (_router == address(0) || _link == address(0) || _goldToken == address(0)) {
            revert InvalidSender(address(0));
        }

        link = _link;
        goldToken = _goldToken;
        destinationChainSelector = _destinationChainSelector;

        whitelistedChains[_destinationChainSelector] = true;
        emit ChainWhitelisted(_destinationChainSelector);

        _ccipGasLimit = 200_000; // Default gas limit
        _allowOutOfOrderExecution = true; // Default to allow out of order execution
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Bridges tokens using LINK token for fee payment
     * @param receiver The address that will receive tokens on the destination chain
     * @param amount The amount of tokens to bridge
     * @return messageId The unique identifier for this bridge transaction
     */
    function bridgeTokensPayLink(address receiver, uint256 amount) external returns (bytes32 messageId) {
        return _bridgeTokens(receiver, amount, link);
    }

    /**
     * @notice Bridges tokens using native currency (ETH/BNB) for fee payment
     * @param receiver The address that will receive tokens on the destination chain
     * @param amount The amount of tokens to bridge
     * @return messageId The unique identifier for this bridge transaction
     */
    function bridgeTokensPayNative(address receiver, uint256 amount) external payable returns (bytes32 messageId) {
        return _bridgeTokens(receiver, amount, address(0));
    }

    /**
     * @notice Internal function to handle the token bridging logic
     * @dev Handles the actual token transfer and CCIP message creation
     * @param receiver The address that will receive tokens
     * @param amount The amount of tokens to bridge
     * @param feeToken The token used to pay CCIP fees (LINK or native token)
     * @return messageId The unique identifier for this bridge transaction
     */
    function _bridgeTokens(address receiver, uint256 amount, address feeToken) internal returns (bytes32 messageId) {
        if (_paused) revert BridgePaused();
        if (amount == 0) revert InvalidAmount(amount);
        if (!whitelistedChains[destinationChainSelector]) revert ChainNotWhitelisted(destinationChainSelector);

        // Transfer tokens from sender
        IERC20(goldToken).safeTransferFrom(msg.sender, address(this), amount);

        // Prepare CCIP message
        Client.EVM2AnyMessage memory message = _buildCCIPMessage(receiver, amount, feeToken);

        // Calculate fees
        uint256 fees = IRouterClient(getRouter()).getFee(destinationChainSelector, message);

        // Check fee balance
        if (feeToken == address(0)) {
            if (msg.value < fees) revert NotEnoughBalance(msg.value, fees);
        } else {
            if (IERC20(feeToken).balanceOf(address(this)) < fees) {
                revert NotEnoughBalance(IERC20(feeToken).balanceOf(address(this)), fees);
            }
            IERC20(feeToken).safeApprove(getRouter(), fees);
        }

        // Send message
        messageId = IRouterClient(getRouter()).ccipSend{value: feeToken == address(0) ? fees : 0}(
            destinationChainSelector, message
        );

        emit TokensBridged(messageId, msg.sender, receiver, amount, destinationChainSelector, feeToken, fees);
    }

    /**
     * @notice Builds the CCIP message for cross-chain communication
     * @dev Creates an EVM2AnyMessage struct with all necessary parameters
     * @param receiver The address that will receive tokens
     * @param amount The amount of tokens being transferred
     * @param feeToken The token used for paying fees
     * @return message The constructed CCIP message
     */
    function _buildCCIPMessage(address receiver, uint256 amount, address feeToken)
        internal
        view
        returns (Client.EVM2AnyMessage memory)
    {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: _ccipGasLimit, allowOutOfOrderExecution: _allowOutOfOrderExecution})
            ),
            feeToken: feeToken
        });
    }

    /**
     * @notice Handles incoming CCIP messages
     * @dev Processes messages received from other chains
     * @param message The CCIP message containing transfer details
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        if (_paused) revert BridgePaused();
        if (processedMessages[message.messageId]) revert MessageAlreadyProcessed(message.messageId);
        if (!whitelistedChains[message.sourceChainSelector]) revert ChainNotWhitelisted(message.sourceChainSelector);

        address sender = abi.decode(message.sender, (address));
        if (!whitelistedSenders[sender]) revert SenderNotWhitelisted(sender);

        (address receiver, uint256 amount) = abi.decode(message.data, (address, uint256));
        if (amount == 0) revert InvalidAmount(amount);

        processedMessages[message.messageId] = true;

        IERC20(goldToken).safeTransfer(receiver, amount);

        emit TokensReceived(message.messageId, receiver, amount, message.sourceChainSelector);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Updates the whitelist status of a chain
     * @param chainSelector The chain selector to update
     * @param enabled Whether to enable or disable the chain
     */
    function setWhitelistedChain(uint64 chainSelector, bool enabled) external onlyOwner {
        whitelistedChains[chainSelector] = enabled;
        if (enabled) {
            emit ChainWhitelisted(chainSelector);
        } else {
            emit ChainRemoved(chainSelector);
        }
    }

    /**
     * @notice Updates the whitelist status of a sender address
     * @param sender The address to update
     * @param enabled Whether to enable or disable the sender
     */
    function setWhitelistedSender(address sender, bool enabled) external onlyOwner {
        if (sender == address(0)) revert InvalidSender(sender);
        whitelistedSenders[sender] = enabled;
        if (enabled) {
            emit SenderWhitelisted(sender);
        } else {
            emit SenderRemoved(sender);
        }
    }

    /**
     * @notice Updates the gas limit for CCIP operations
     * @param gasLimit The new gas limit to set
     */
    function setCCIPGasLimit(uint256 gasLimit) external onlyOwner {
        _ccipGasLimit = gasLimit;
        emit CCIPGasLimitUpdated(gasLimit);
    }

    /**
     * @notice Updates the out-of-order execution setting
     * @param allow Whether to allow out-of-order execution
     */
    function setAllowOutOfOrderExecution(bool allow) external onlyOwner {
        _allowOutOfOrderExecution = allow;
        emit OutOfOrderExecutionUpdated(allow);
    }

    /**
     * @notice Pauses the bridge
     * @dev Prevents any new bridge operations from being executed
     */
    function pauseBridge() external onlyOwner {
        if (_paused) revert BridgeNotPaused();
        _paused = true;
        emit BridgePaused();
    }

    /**
     * @notice Unpauses the bridge
     * @dev Allows bridge operations to be executed again
     */
    function unpauseBridge() external onlyOwner {
        if (!_paused) revert BridgePaused();
        _paused = false;
        emit BridgeUnpaused();
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Checks if the bridge is paused
     * @return bool True if the bridge is paused, false otherwise
     */
    function isPaused() external view returns (bool) {
        return _paused;
    }

    /**
     * @notice Gets the LINK token balance of the contract
     * @return uint256 The amount of LINK tokens held by the contract
     */
    function getLinkBalance() external view returns (uint256) {
        return IERC20(link).balanceOf(address(this));
    }

    /**
     * @notice Gets the GoldToken balance of the contract
     * @return uint256 The amount of GoldTokens held by the contract
     */
    function getGoldTokenBalance() external view returns (uint256) {
        return IERC20(goldToken).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Allows the contract to receive native currency
    receive() external payable {}

    /**
     * @notice Withdraws all native currency from the contract
     * @param beneficiary The address to receive the withdrawn currency
     */
    function withdraw(address beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert InvalidAmount(0);

        (bool sent,) = beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, beneficiary, amount);
    }

    /**
     * @notice Withdraws all tokens of a specific type from the contract
     * @param beneficiary The address to receive the withdrawn tokens
     * @param token The token contract address to withdraw
     */
    function withdrawToken(address beneficiary, address token) public onlyOwner {
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) revert InvalidAmount(0);

        IERC20(token).safeTransfer(beneficiary, amount);
    }
}
