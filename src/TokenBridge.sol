// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ITokenBridge} from "./interfaces/ITokenBridge.sol";
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

/**
 * @title TokenBridge
 * @notice Cross-chain bridge for GoldToken using Chainlink's CCIP protocol
 * @dev Implements a secure bridge between Ethereum and BSC networks using Chainlink's CCIP.
 *      This contract handles:
 *      - Cross-chain token transfers with both LINK and native token fee payments
 *      - Message verification and processing
 *      - Chain and sender whitelisting
 *      - Emergency pause functionality
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
        _onlyEnabledChain(chainSelector);
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
     * @inheritdoc ITokenBridge
     * @dev Sets up initial chain configuration with default CCIP gas parameters for the destination chain
     */
    function initialize(address owner, address _link, address _goldToken, uint64 _destinationChainSelector)
        external
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
        emit TokenBridgeInitialized(owner, _link, _goldToken, _destinationChainSelector);
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

    /// @inheritdoc ITokenBridge
    function bridgeTokens(address receiver, uint256 amount, PayFeesIn payFeesIn)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (bytes32)
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
        private
        onlyEnabledChain(destinationChainSelector)
        returns (bytes32)
    {
        if (amount == 0) revert InvalidAmount(amount);
        if (receiver == address(0)) revert InvalidSender(receiver);

        IERC20 gold = IERC20(goldToken);
        gold.safeTransferFrom(msg.sender, address(this), amount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: goldToken, amount: amount});

        gold.forceApprove(getRouter(), amount);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: abi.encode(receiver),
            tokenAmounts: tokenAmounts,
            extraArgs: _chainDetails[destinationChainSelector].ccipExtraArgs,
            feeToken: feeToken
        });

        IRouterClient router = IRouterClient(getRouter());
        uint256 fees = router.getFee(destinationChainSelector, message);

        if (feeToken == address(0)) {
            if (msg.value < fees) revert NotEnoughBalance(msg.value, fees);
        } else {
            if (fees > 0) {
                uint256 feeBalance = IERC20(feeToken).balanceOf(address(this));
                if (feeBalance < fees) {
                    revert NotEnoughBalance(feeBalance, fees);
                }
                IERC20(feeToken).forceApprove(getRouter(), fees);
            }
        }

        bytes32 messageId = router.ccipSend{value: feeToken == address(0) ? fees : 0}(destinationChainSelector, message);

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

        bool foundGoldToken;
        uint256 tokenAmount;

        uint256 tokensLength = message.destTokenAmounts.length;
        if (tokensLength > 0) {
            for (uint256 i; i < tokensLength; ++i) {
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
            emit MessageProcessedWithoutToken(message.messageId, message.sourceChainSelector);
        }
    }

    /**
     * @notice Ensures operations only proceed with whitelisted chains
     * @dev Unwrapped onlyEnabledChain modifier logic to reduce bytecode size
     * @param chainSelector The chain selector to verify
     */
    function _onlyEnabledChain(uint64 chainSelector) private view {
        if (!_chainDetails[chainSelector].isEnabled) {
            revert ChainNotWhitelisted(chainSelector);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITokenBridge
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

    /// @inheritdoc ITokenBridge
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

    /// @inheritdoc ITokenBridge
    function withdraw(address beneficiary) external override onlyRole(OWNER_ROLE) nonReentrant {
        uint256 amount = address(this).balance;
        if (amount == 0) revert InvalidAmount(0);
        if (beneficiary == address(0)) revert InvalidSender(address(0));

        (bool sent,) = beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, beneficiary, amount);
    }

    /// @inheritdoc ITokenBridge
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

    /// @inheritdoc ITokenBridge
    function whitelistedChains(uint64 chainSelector) external view override returns (bool) {
        return _chainDetails[chainSelector].isEnabled;
    }

    /// @inheritdoc ITokenBridge
    function getLinkBalance() external view override returns (uint256) {
        return IERC20(link).balanceOf(address(this));
    }

    /// @inheritdoc ITokenBridge
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
