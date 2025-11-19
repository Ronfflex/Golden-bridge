// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IGoldToken} from "./interfaces/IGoldToken.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GoldToken
 * @notice ERC-20 token representing on-chain grams of gold redeemable via ETH deposits and burns
 * @dev Upgradeable (UUPS) contract that relies on Chainlink price feeds and exposes hooks for the Lotterie module
 */
contract GoldToken is
    Initializable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    IGoldToken
{
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role identifier governing privileged token operations and upgrades
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    AggregatorV3Interface internal _dataFeedGold;
    AggregatorV3Interface internal _dataFeedEth;

    uint256 internal _fees;
    address internal _feesAddress;
    address internal _lotterieAddress;

    uint256 internal _minimumGoldToBlock;
    mapping(address => uint256) internal _timestamps;
    address[] internal _users;

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Locks the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IGoldToken
    function initialize(address owner, address dataFeedGoldAddress, address dataFeedEthAddress)
        external
        override
        initializer
    {
        __ERC20_init("Gold", "GLD");
        __ERC20Pausable_init();
        __AccessControl_init();

        _grantRole(OWNER_ROLE, owner);

        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);

        _dataFeedGold = AggregatorV3Interface(
            dataFeedGoldAddress // 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea
        );
        _dataFeedEth = AggregatorV3Interface(
            dataFeedEthAddress // 0x694AA1769357215DE4FAC081bf1f309aDC325306
        );

        _fees = 5; // 5%
        _feesAddress = owner;
        _minimumGoldToBlock = 1 ether; // 1 GLD

        emit GoldTokenInitialized(owner, dataFeedGoldAddress, dataFeedEthAddress);
    }

    /// @dev Restricts upgrades to addresses holding OWNER_ROLE
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(OWNER_ROLE) {}

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGoldToken
    function addOwner(address account) external override onlyRole(OWNER_ROLE) {
        grantRole(OWNER_ROLE, account);
    }

    /// @inheritdoc IGoldToken
    function removeOwner(address account) external override onlyRole(OWNER_ROLE) {
        revokeRole(OWNER_ROLE, account);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGoldToken
    function claimEth() external override onlyRole(OWNER_ROLE) nonReentrant {
        uint256 payout = address(this).balance;
        (bool success,) = payable(msg.sender).call{value: payout}("");
        if (!success) {
            revert EthTransferFailed();
        }
    }

    /// @inheritdoc IGoldToken
    function setFeesAddress(address feesAddress) external override onlyRole(OWNER_ROLE) {
        address previous = _feesAddress;
        _feesAddress = feesAddress;
        emit FeesAddressUpdated(previous, feesAddress);
    }

    /// @inheritdoc IGoldToken
    function setLotterieAddress(address lotterieAddress) external override onlyRole(OWNER_ROLE) {
        address previous = _lotterieAddress;
        _lotterieAddress = lotterieAddress;
        emit LotterieAddressUpdated(previous, lotterieAddress);
    }

    /// @inheritdoc IGoldToken
    function pause() external override onlyRole(OWNER_ROLE) {
        _pause();
    }

    /// @inheritdoc IGoldToken
    function unpause() external override onlyRole(OWNER_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IGoldToken
     * @dev Applies protocol fees split between Lotterie and fee recipient, tracking lottery eligibility
     */
    function mint() external payable override whenNotPaused {
        if (msg.value == 0) {
            revert ValueMustBeGreaterThanZero();
        }

        int256 goldPriceInEth = getGoldPriceInEth();
        if (goldPriceInEth <= 0) {
            revert InvalidGoldPrice();
        }

        // casting to uint256 is safe because goldPriceInEth is verified to be strictly positive above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 goldPriceScaled = uint256(goldPriceInEth) * 10 ** 10; // 10**8 + 10**10 = 10**18
        uint256 goldAmount = msg.value * 10 ** 18 / goldPriceScaled;
        if (goldAmount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        uint256 fee = goldAmount * _fees / 100;

        goldAmount -= fee;
        uint256 lotterieFee = fee / 2;

        _addUser(msg.sender);

        _mint(msg.sender, goldAmount);
        _mint(_lotterieAddress, lotterieFee);
        _mint(_feesAddress, fee - lotterieFee);

        emit Mint(msg.sender, goldAmount);
    }

    /// @inheritdoc IGoldToken
    function burn(uint256 amount) external override whenNotPaused {
        _burn(msg.sender, amount);
        if (balanceOf(msg.sender) <= _minimumGoldToBlock) {
            _removeUser(msg.sender);
        }
    }

    /// @inheritdoc IGoldToken
    function transfer(address to, uint256 amount) public override(ERC20Upgradeable, IGoldToken) returns (bool) {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }
        if (msg.sender != _lotterieAddress && balanceOf(msg.sender) <= _minimumGoldToBlock) {
            _removeUser(msg.sender);
        }
        _addUser(to);
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @dev Removes a user from the lottery pool and clears their timestamp
    function _removeUser(address user) private {
        _timestamps[user] = 0;
        uint256 length = _users.length;
        for (uint256 i; i < length; i++) {
            if (_users[i] == user) {
                _users[i] = _users[_users.length - 1];
                _users.pop();
                emit UserRemoved(user);
                break;
            }
        }
    }

    /// @dev Adds a user to the lottery pool on first interaction
    function _addUser(address user) private {
        if (_timestamps[user] == 0) {
            _users.push(user);
            _timestamps[user] = block.timestamp;
            emit UserAdded(user, block.timestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGoldToken
    function getGoldPriceInEth() public view override returns (int256) {
        (, int256 goldUsdPerTroyOunce,,,) = _dataFeedGold.latestRoundData(); // Price per troy ounce (31.1034768 g) = x USD (8 decimals)
        int256 goldUsdPerGram = (goldUsdPerTroyOunce * 10_000_000) / 311_034_768;

        (, int256 ethUsd,,,) = _dataFeedEth.latestRoundData(); // 1 ETH = y USD (8 decimals)
        return goldUsdPerGram * 10 ** 8 / ethUsd;
    }

    /// @inheritdoc IGoldToken
    function getFees() external view override returns (uint256) {
        return _fees;
    }

    /// @inheritdoc IGoldToken
    function getFeesAddress() external view override returns (address) {
        return _feesAddress;
    }

    /// @inheritdoc IGoldToken
    function getUsers() external view override returns (address[] memory) {
        return _users;
    }

    /// @inheritdoc IGoldToken
    function getTimestamps() external view override returns (address[] memory, uint256[] memory) {
        uint256 length = _users.length;
        uint256[] memory timestamps = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            timestamps[i] = _timestamps[_users[i]];
        }
        return (_users, timestamps);
    }

    /// @inheritdoc IGoldToken
    function hasOwnerRole(address account) external view override returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }

    /// @inheritdoc IGoldToken
    function balanceOf(address account) public view override(ERC20Upgradeable, IGoldToken) returns (uint256) {
        return super.balanceOf(account);
    }
}
