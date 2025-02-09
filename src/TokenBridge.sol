// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {ITokenBridge} from "./interfaces/ITokenBridge.sol";

/**
 * @title TokenBridge
 * @notice Cross-chain bridge for GoldToken using Chainlink's CCIP protocol
 * @dev Implements a secure bridge between Ethereum and BSC networks using Chainlink's CCIP.
 *      This contract handles:
 *      - Cross-chain token transfers with both LINK and native token fee payments
 *      - Message verification and processing
 *      - Chain and sender whitelisting
 *      - Emergency pause functionality
 *      - Security features including reentrancy protection
 */
contract TokenBridge is CCIPReceiver, OwnerIsCreator, Pausable, ReentrancyGuard, ITokenBridge {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Stores configuration details for each supported chain
     * @param isEnabled Whether the chain is currently whitelisted
     * @param ccipExtraArgs Extra arguments for CCIP message configuration
     */
    struct ChainDetails {
        bool isEnabled;
        bytes ccipExtraArgs;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Chain selector for the authorized destination chain (BSC)
    /// @dev Immutable value set during deployment
    uint64 public immutable override destinationChainSelector;

    /// @notice Contract address of the GoldToken being bridged
    /// @dev Immutable value set during deployment
    address public immutable override goldToken;

    /// @notice Contract address of LINK token used for fee payments
    /// @dev Immutable value set during deployment
    address public immutable override link;

    /// @notice Tracks processed CCIP messages to prevent duplicates
    /// @dev Maps messageId => processed status
    mapping(bytes32 => bool) public override processedMessages;

    /// @notice Stores configuration for each supported chain
    /// @dev Maps chainSelector => ChainDetails
    mapping(uint64 => ChainDetails) private _chainDetails;

    /// @notice Tracks authorized cross-chain senders
    /// @dev Maps sender address => authorization status
    mapping(address => bool) public override whitelistedSenders;

    /// @notice Gas limit for cross-chain operations
    /// @dev Default value 200,000, can be updated by owner
    uint256 private _ccipGasLimit;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensures operations only proceed with whitelisted chains
     * @param chainSelector The chain selector to verify
     */
    modifier onlyEnabledChain(uint64 chainSelector) {
        if (!_chainDetails[chainSelector].isEnabled) {
            revert ChainNotWhitelisted(chainSelector);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the bridge with router, token addresses, and destination chain
     * @dev Sets up initial chain configuration with default parameters
     * @param _router Address of the CCIP router contract
     * @param _link Address of the LINK token contract
     * @param _goldToken Address of the GoldToken contract
     * @param _destinationChainSelector Selector for the destination chain
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

        _chainDetails[_destinationChainSelector] = ChainDetails({
            isEnabled: true,
            ccipExtraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true}))
        });

        emit ChainWhitelisted(_destinationChainSelector);
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bridges tokens to the destination chain
     * @dev Handles both LINK and native token fee payments
     * @param receiver Address receiving tokens on destination chain
     * @param amount Amount of tokens to bridge
     * @param payFeesIn Specifies fee payment method (LINK or native)
     * @return messageId Unique identifier for the bridge transaction
     */
    function bridgeTokens(address receiver, uint256 amount, PayFeesIn payFeesIn)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (bytes32 messageId)
    {
        address feeToken = payFeesIn == PayFeesIn.LINK ? link : address(0);
        return _bridgeTokens(receiver, amount, feeToken);
    }

    /**
     * @dev Internal function to handle token bridging logic
     * @param receiver Address receiving the tokens
     * @param amount Amount of tokens to bridge
     * @param feeToken Token used for fee payment (LINK or native)
     * @return messageId Unique identifier for the transaction
     */
    function _bridgeTokens(address receiver, uint256 amount, address feeToken)
        internal
        onlyEnabledChain(destinationChainSelector)
        returns (bytes32 messageId)
    {
        if (amount == 0) revert InvalidAmount(amount);

        IERC20(goldToken).safeTransferFrom(msg.sender, address(this), amount);

        Client.EVM2AnyMessage memory message = _buildCCIPMessage(receiver, amount, feeToken);

        uint256 fees = IRouterClient(getRouter()).getFee(destinationChainSelector, message);

        if (feeToken == address(0)) {
            if (msg.value < fees) revert NotEnoughBalance(msg.value, fees);
        } else {
            if (IERC20(feeToken).balanceOf(address(this)) < fees) {
                revert NotEnoughBalance(IERC20(feeToken).balanceOf(address(this)), fees);
            }
            IERC20(feeToken).approve(getRouter(), fees);
        }

        messageId = IRouterClient(getRouter()).ccipSend{value: feeToken == address(0) ? fees : 0}(
            destinationChainSelector, message
        );

        emit TokensBridged(messageId, msg.sender, receiver, amount, destinationChainSelector, feeToken, fees);
    }

    /**
     * @dev Builds the CCIP message for cross-chain communication
     * @param receiver Address receiving the tokens
     * @param amount Amount of tokens being transferred
     * @param feeToken Token used for fee payment
     * @return CCIP message structure
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
            extraArgs: _chainDetails[destinationChainSelector].ccipExtraArgs,
            feeToken: feeToken
        });
    }

    /**
     * @notice Processes incoming CCIP messages
     * @dev Handles message verification and token distribution
     * @param message The incoming CCIP message
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override whenNotPaused nonReentrant {
        if (processedMessages[message.messageId]) {
            revert MessageAlreadyProcessed(message.messageId);
        }
        if (!_chainDetails[message.sourceChainSelector].isEnabled) {
            revert ChainNotWhitelisted(message.sourceChainSelector);
        }

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
     * @notice Updates chain whitelist status and configuration
     * @dev Sets chain status and CCIP message parameters
     * @param chainSelector The chain selector to update
     * @param enabled Whether to enable or disable the chain
     * @param ccipExtraArgs CCIP message configuration for the chain
     */
    function setWhitelistedChain(uint64 chainSelector, bool enabled, bytes memory ccipExtraArgs)
        external
        override
        onlyOwner
    {
        if (chainSelector == 0) revert InvalidChainSelector(chainSelector);

        _chainDetails[chainSelector] = ChainDetails({isEnabled: enabled, ccipExtraArgs: ccipExtraArgs});

        if (enabled) {
            emit ChainWhitelisted(chainSelector);
        } else {
            emit ChainRemoved(chainSelector);
        }
    }

    /**
     * @notice Updates sender whitelist status
     * @param sender The sender address to update
     * @param enabled Whether to enable or disable the sender
     */
    function setWhitelistedSender(address sender, bool enabled) external override onlyOwner {
        if (sender == address(0)) revert InvalidSender(sender);
        whitelistedSenders[sender] = enabled;
        if (enabled) {
            emit SenderWhitelisted(sender);
        } else {
            emit SenderRemoved(sender);
        }
    }

    /**
     * @notice Pauses bridge operations
     * @dev Can only be called by the owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses bridge operations
     * @dev Can only be called by the owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows the contract to receive native tokens
    receive() external payable {}

    /**
     * @notice Withdraws native tokens from the contract
     * @param beneficiary Address to receive the withdrawn tokens
     */
    function withdraw(address beneficiary) external override onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        if (amount == 0) revert InvalidAmount(0);

        (bool sent,) = beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, beneficiary, amount);
    }

    /**
     * @notice Withdraws ERC20 tokens from the contract
     * @param beneficiary Address to receive the withdrawn tokens
     * @param token Address of the token to withdraw
     */
    function withdrawToken(address beneficiary, address token) external override onlyOwner nonReentrant {
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) revert InvalidAmount(0);

        IERC20(token).safeTransfer(beneficiary, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if a chain is whitelisted
     * @param chainSelector The chain selector to check
     * @return bool True if the chain is whitelisted
     */
    function whitelistedChains(uint64 chainSelector) external view override returns (bool) {
        return _chainDetails[chainSelector].isEnabled;
    }

    /**
     * @notice Gets the contract's LINK token balance
     * @return uint256 The contract's LINK token balance
     */
    function getLinkBalance() external view override returns (uint256) {
        return IERC20(link).balanceOf(address(this));
    }

    /**
     * @notice Gets the contract's GoldToken balance
     * @return uint256 The contract's GoldToken balance
     */
    function getGoldTokenBalance() external view override returns (uint256) {
        return IERC20(goldToken).balanceOf(address(this));
    }
}
