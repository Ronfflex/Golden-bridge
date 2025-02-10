// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title GoldToken
 * @dev This contract implements a token that can be minted and burned, with fees and lottery functionality.
 * It uses Chainlink price feeds to determine the gold price in ETH.
 * The contract is upgradeable and utilizes Access Control for owner management.
 */
contract GoldToken is Initializable, ERC20PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    AggregatorV3Interface internal _dataFeedGold;
    AggregatorV3Interface internal _dataFeedEth;

    uint256 internal _fees;
    address internal _feesAddress;
    address internal _lotterieAddress;

    uint256 internal _minimumGoldToBlock;
    mapping(address => uint256) internal _timestamps;
    address[] internal _users;

    error ValueMustBeGreaterThanZero();
    error AmountMustBeGreaterThanZero();

    /**
     * @dev Emitted when tokens are minted.
     * @param to The address that will receive the minted tokens.
     * @param amount The amount of tokens minted.
     */
    event Mint(address indexed to, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract setting the owner and data feed addresses.
     * @param owner The address of the owner.
     * @param dataFeedGoldAddress The address of the gold price data feed.
     * @param dataFeedEthAddress The address of the ETH price data feed.
     */
    function initialize(address owner, address dataFeedGoldAddress, address dataFeedEthAddress) public initializer {
        __ERC20_init("Gold", "GLD");
        __ERC20Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

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
    }

    /**
     * @dev Authorizes the upgrade of the contract.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(OWNER_ROLE) {}

    /**
     * @dev Adds a new owner to the contract.
     * @param account The address of the new owner.
     */
    function addOwner(address account) external onlyRole(OWNER_ROLE) {
        grantRole(OWNER_ROLE, account);
    }

    /**
     * @dev Removes an owner from the contract.
     * @param account The address of the owner to be removed.
     */
    function removeOwner(address account) external onlyRole(OWNER_ROLE) {
        revokeRole(OWNER_ROLE, account);
    }

    /**
     * @dev Pauses the contract, preventing minting and burning.
     */
    function pause() external onlyRole(OWNER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract, allowing minting and burning.
     */
    function unpause() external onlyRole(OWNER_ROLE) {
        _unpause();
    }

    /**
     * @dev Mints new tokens based on the ETH sent to the contract.
     * Reverts if the value sent is zero or if the calculated gold amount is zero.
     */
    function mint() external payable whenNotPaused {
        if (msg.value == 0) {
            revert ValueMustBeGreaterThanZero();
        }

        int256 goldPriceInEth = getGoldPriceInEth() * 10 ** 10; // 10**8 + 10**10 = 10**18
        uint256 goldAmount = msg.value * 10 ** 18 / uint256(goldPriceInEth);
        if (goldAmount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        uint256 fee = goldAmount * _fees / 100;

        goldAmount -= fee;
        uint256 lotterieFee = fee / 2;

        addUser(msg.sender);

        _mint(msg.sender, goldAmount);
        _mint(_lotterieAddress, lotterieFee);
        _mint(_feesAddress, fee - lotterieFee);

        emit Mint(msg.sender, goldAmount);
    }

    /**
     * @dev Burns a specified amount of tokens from the caller's account.
     * @param amount The amount of tokens to burn.
     */
    function burn(uint256 amount) external whenNotPaused {
        _burn(msg.sender, amount);
        if (balanceOf(msg.sender) <= _minimumGoldToBlock) {
            removeUser(msg.sender);
        }
    }

    /**
     * @dev Transfers tokens from the caller to another address.
     * @param to The address to transfer tokens to.
     * @param amount The amount of tokens to transfer.
     * @return True if the transfer was successful.
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(amount > 0, AmountMustBeGreaterThanZero());
        if(msg.sender != _lotterieAddress && balanceOf(msg.sender) <= _minimumGoldToBlock) {
            removeUser(msg.sender);
        }
        addUser(to);
        _transfer(msg.sender, to, amount);
        return true;
    }

    function removeUser(address user) internal {
        _timestamps[user] = 0;
        for (uint256 i = 0; i < _users.length; i++) {
            if (_users[i] == user) {
                _users[i] = _users[_users.length - 1];
                _users.pop();
                break;
            }
        }
    }

    function addUser(address user) internal {
        if (_timestamps[user] == 0) {
            _users.push(user);
            _timestamps[user] = block.timestamp;
        }
    }

    /**
     * @dev Gets the current gold price in ETH.
     * @return The price of gold in ETH.
     */
    function getGoldPriceInEth() public view returns (int256) {
        (, int256 goldUsd,,,) = _dataFeedGold.latestRoundData(); // 31,1 gold = x USD
        goldUsd = goldUsd / 311; // 1 gold = (goldUsd / 311) USD
        (, int256 ethUsd,,,) = _dataFeedEth.latestRoundData(); // 1 ETH = y USD
        return goldUsd * 10 ** 8 / ethUsd; // 1 gold = (goldUsd / ethUsd) ETH
    }

    /**
     * @dev Gets the current fees percentage.
     * @return The fees percentage.
     */
    function getFees() external view returns (uint256) {
        return _fees;
    }

    /**
     * @dev Gets the address where fees are sent.
     * @return The fees address.
     */
    function getFeesAddress() external view returns (address) {
        return _feesAddress;
    }

    /**
     * @dev Gets the list of users who have interacted with the contract.
     * @return An array of user addresses.
     */
    function getUsers() external view returns (address[] memory) {
        return _users;
    }

    /**
     * @dev Gets the timestamps of user interactions.
     * @return An array of user addresses and their corresponding timestamps.
     */
    function getTimestamps() external view returns (address[] memory, uint256[] memory) {
        uint256 length = _users.length;
        uint256[] memory timestamps = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            timestamps[i] = _timestamps[_users[i]];
        }
        return (_users, timestamps);
    }

    /**
     * @dev Checks if an account has the owner role.
     * @param account The address to check.
     * @return True if the account has the owner role, false otherwise.
     */
    function hasOwnerRole(address account) external view returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }

    /**
     * @dev Sets the address where fees are sent.
     * @param feesAddress The new fees address.
     */
    function setFeesAddress(address feesAddress) external onlyRole(OWNER_ROLE) {
        // Lotterie contract
        _feesAddress = feesAddress;
    }

    /**
     * @dev Sets the address of the lottery contract.
     * @param lotterieAddress The new lottery address.
     */
    function setLotterieAddress(address lotterieAddress) external onlyRole(OWNER_ROLE) {
        _lotterieAddress = lotterieAddress;
    }

    /**
     * @dev Claims all ETH held by the contract and sends it to the caller.
     */
    function claimEth() external onlyRole(OWNER_ROLE) {
        payable(msg.sender).transfer(address(this).balance);
    }
}
