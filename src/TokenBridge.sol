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
 * @dev Enables secure token transfer between Ethereum and BSC networks
 * @custom:security-contact security@goldbridge.com
 */
contract TokenBridge is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint64 public immutable destinationChainSelector;
    address public immutable goldToken;
    address public immutable link;

    mapping(bytes32 => bool) public processedMessages;
    mapping(uint64 => bool) public whitelistedChains;
    mapping(address => bool) public whitelistedSenders;
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
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Bridges tokens using LINK for fees
     * @param receiver Address that will receive tokens on destination chain
     * @param amount Amount of tokens to bridge
     */
    function bridgeTokensPayLink(address receiver, uint256 amount) external returns (bytes32 messageId) {
        return _bridgeTokens(receiver, amount, link);
    }

    /**
     * @notice Bridges tokens using native currency for fees
     * @param receiver Address that will receive tokens on destination chain
     * @param amount Amount of tokens to bridge
     */
    function bridgeTokensPayNative(address receiver, uint256 amount) external payable returns (bytes32 messageId) {
        return _bridgeTokens(receiver, amount, address(0));
    }

    /**
     * @dev Internal function to handle token bridging
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

    function _buildCCIPMessage(address receiver, uint256 amount, address feeToken)
        internal
        pure
        returns (Client.EVM2AnyMessage memory)
    {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true})),
            feeToken: feeToken
        });
    }

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
    function setWhitelistedChain(uint64 chainSelector, bool enabled) external onlyOwner {
        whitelistedChains[chainSelector] = enabled;
        if (enabled) {
            emit ChainWhitelisted(chainSelector);
        } else {
            emit ChainRemoved(chainSelector);
        }
    }

    function setWhitelistedSender(address sender, bool enabled) external onlyOwner {
        if (sender == address(0)) revert InvalidSender(sender);
        whitelistedSenders[sender] = enabled;
        if (enabled) {
            emit SenderWhitelisted(sender);
        } else {
            emit SenderRemoved(sender);
        }
    }

    function pauseBridge() external onlyOwner {
        if (_paused) revert BridgeNotPaused();
        _paused = true;
        emit BridgePaused();
    }

    function unpauseBridge() external onlyOwner {
        if (!_paused) revert BridgePaused();
        _paused = false;
        emit BridgeUnpaused();
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function isPaused() external view returns (bool) {
        return _paused;
    }

    function getLinkBalance() external view returns (uint256) {
        return IERC20(link).balanceOf(address(this));
    }

    function getGoldTokenBalance() external view returns (uint256) {
        return IERC20(goldToken).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    receive() external payable {}

    function withdraw(address beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert InvalidAmount(0);

        (bool sent,) = beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, beneficiary, amount);
    }

    function withdrawToken(address beneficiary, address token) public onlyOwner {
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) revert InvalidAmount(0);

        IERC20(token).safeTransfer(beneficiary, amount);
    }
}
