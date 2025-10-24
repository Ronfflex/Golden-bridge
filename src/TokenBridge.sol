// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
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
contract TokenBridge is
    Initializable,
    CCIPReceiver,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable,
    ITokenBridge
{
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

    /// @notice Role identifier for owners
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @notice Chain selector for the authorized destination chain (BSC)
    uint64 public override destinationChainSelector;

    /// @notice Contract address of the GoldToken being bridged
    address public override goldToken;

    /// @notice Contract address of LINK token used for fee payments
    address public override link;

    /// @notice Tracks processed CCIP messages to prevent duplicates
    /// @dev Maps messageId => processed status
    mapping(bytes32 => bool) public override processedMessages;

    /// @notice Stores configuration for each supported chain
    /// @dev Maps chainSelector => ChainDetails
    mapping(uint64 => ChainDetails) private _chainDetails;

    /// @notice Tracks authorized cross-chain senders
    /// @dev Maps sender address => authorization status
    mapping(address => bool) public override whitelistedSenders;

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
                       CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _router) CCIPReceiver(_router) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the bridge with router, token addresses, and destination chain
     * @dev Sets up initial chain configuration with default parameters
     * @param owner Admin address for the contract
     * @param _link Address of the LINK token contract
     * @param _goldToken Address of the GoldToken contract
     * @param _destinationChainSelector Selector for the destination chain
     */
    function initialize(address owner, address _link, address _goldToken, uint64 _destinationChainSelector)
        public
        initializer
    {
        __AccessControl_init();
        __Pausable_init();

        if (_link == address(0) || _goldToken == address(0)) {
            revert InvalidSender(address(0));
        }

        _grantRole(OWNER_ROLE, owner);
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);

        link = _link;
        goldToken = _goldToken;
        destinationChainSelector = _destinationChainSelector;

        _chainDetails[_destinationChainSelector] = ChainDetails({
            isEnabled: true,
            ccipExtraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true})
            )
        });

        emit ChainWhitelisted(_destinationChainSelector);
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract
     */
    function _authorizeUpgrade(address) internal override onlyRole(OWNER_ROLE) {}

    /**
     * @dev Resolves the conflict between CCIPReceiver and AccessControlUpgradeable
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, CCIPReceiver)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new owner to the contract
     * @param account Address to be granted owner role
     */
    function addOwner(address account) external onlyRole(OWNER_ROLE) {
        grantRole(OWNER_ROLE, account);
    }

    /**
     * @notice Removes an owner from the contract
     * @param account Address to be revoked owner role
     */
    function removeOwner(address account) external onlyRole(OWNER_ROLE) {
        revokeRole(OWNER_ROLE, account);
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
        if (receiver == address(0)) revert InvalidSender(receiver);

        IERC20(goldToken).safeTransferFrom(msg.sender, address(this), amount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: goldToken, amount: amount});

        IERC20(goldToken).approve(getRouter(), amount);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: abi.encode(receiver),
            tokenAmounts: tokenAmounts,
            extraArgs: _chainDetails[destinationChainSelector].ccipExtraArgs,
            feeToken: feeToken
        });

        uint256 fees = IRouterClient(getRouter()).getFee(destinationChainSelector, message);

        if (feeToken == address(0)) {
            if (msg.value < fees) revert NotEnoughBalance(msg.value, fees);
        } else {
            if (IERC20(feeToken).balanceOf(address(this)) < fees) {
                revert NotEnoughBalance(IERC20(feeToken).balanceOf(address(this)), fees);
            }
            IERC20(feeToken).approve(getRouter(), fees);
        }

        // Send CCIP message
        messageId = IRouterClient(getRouter()).ccipSend{value: feeToken == address(0) ? fees : 0}(
            destinationChainSelector, message
        );

        emit TokensBridged(messageId, msg.sender, receiver, amount, destinationChainSelector, feeToken, fees);

        return messageId;
    }

    /**
     * @notice Processes incoming CCIP messages
     * @dev Handles message verification and token distribution from CCIP
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

        address receiver = abi.decode(message.data, (address));
        if (receiver == address(0)) revert InvalidSender(address(0));

        bool foundGoldToken = false;
        uint256 tokenAmount = 0;

        if (message.destTokenAmounts.length > 0) {
            for (uint256 i = 0; i < message.destTokenAmounts.length; i++) {
                if (message.destTokenAmounts[i].token == goldToken) {
                    foundGoldToken = true;
                    tokenAmount = message.destTokenAmounts[i].amount;

                    if (tokenAmount == 0) revert InvalidAmount(0);

                    processedMessages[message.messageId] = true;

                    IERC20(goldToken).safeTransfer(receiver, tokenAmount);

                    emit TokensReceived(message.messageId, receiver, tokenAmount, message.sourceChainSelector);
                }
            }
        }

        if (!foundGoldToken) {
            processedMessages[message.messageId] = true;
        }
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
        onlyRole(OWNER_ROLE)
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
    function setWhitelistedSender(address sender, bool enabled) external override onlyRole(OWNER_ROLE) {
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
    function pause() external onlyRole(OWNER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses bridge operations
     * @dev Can only be called by the owner
     */
    function unpause() external onlyRole(OWNER_ROLE) {
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
    function withdraw(address beneficiary) external override onlyRole(OWNER_ROLE) nonReentrant {
        uint256 amount = address(this).balance;
        if (amount == 0) revert InvalidAmount(0);
        if (beneficiary == address(0)) revert InvalidSender(address(0));

        (bool sent,) = beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, beneficiary, amount);
    }

    /**
     * @notice Withdraws ERC20 tokens from the contract
     * @param beneficiary Address to receive the withdrawn tokens
     * @param token Address of the token to withdraw
     */
    function withdrawToken(address beneficiary, address token) external override onlyRole(OWNER_ROLE) nonReentrant {
        if (beneficiary == address(0)) revert InvalidSender(address(0));
        if (token == address(0)) revert InvalidSender(address(0));

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

    /**
     * @notice Checks if an account has the owner role
     * @param account The account to check
     * @return bool True if the account has the owner role
     */
    function hasOwnerRole(address account) external view returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }
}
