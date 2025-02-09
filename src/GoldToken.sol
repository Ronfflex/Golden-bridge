// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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

    event Mint(address indexed to, uint256 amount);

    constructor() {
        _disableInitializers();
    }

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

    function _authorizeUpgrade(address) internal override onlyRole(OWNER_ROLE) {}

    function addOwner(address account) external onlyRole(OWNER_ROLE) {
        grantRole(OWNER_ROLE, account);
    }

    function removeOwner(address account) external onlyRole(OWNER_ROLE) {
        revokeRole(OWNER_ROLE, account);
    }

    function pause() external onlyRole(OWNER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(OWNER_ROLE) {
        _unpause();
    }

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

    function burn(uint256 amount) external whenNotPaused {
        _burn(msg.sender, amount);
        if (balanceOf(msg.sender) <= _minimumGoldToBlock) {
            removeUser(msg.sender);
        }
    }

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

    function getGoldPriceInEth() public view returns (int256) {
        (, int256 goldUsd,,,) = _dataFeedGold.latestRoundData(); // 1 gold = x USD
        (, int256 ethUsd,,,) = _dataFeedEth.latestRoundData(); // 1 ETH = y USD
        return goldUsd * 10 ** 8 / ethUsd; // 1 gold = (goldUsd / ethUsd) ETH
    }

    function getFees() external view returns (uint256) {
        return _fees;
    }

    function getFeesAddress() external view returns (address) {
        return _feesAddress;
    }

    function getUsers() external view returns (address[] memory) {
        return _users;
    }

    function getTimestamps() external view returns (address[] memory, uint256[] memory) {
        uint256 length = _users.length;
        uint256[] memory timestamps = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            timestamps[i] = _timestamps[_users[i]];
        }
        return (_users, timestamps);
    }

    function hasOwnerRole(address account) external view returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }

    function setFeesAddress(address feesAddress) external onlyRole(OWNER_ROLE) {
        // Lotterie contract
        _feesAddress = feesAddress;
    }

    function setLotterieAddress(address lotterieAddress) external onlyRole(OWNER_ROLE) {
        _lotterieAddress = lotterieAddress;
    }

    function claimEth() external onlyRole(OWNER_ROLE) {
        payable(msg.sender).transfer(address(this).balance);
    }
}
