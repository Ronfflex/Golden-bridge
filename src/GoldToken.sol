// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract GoldToken is Initializable, ERC20PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    AggregatorV3Interface internal dataFeed_gold;
    AggregatorV3Interface internal dataFeed_eth;

    uint256 internal fees;
    address internal feesAddress;

    event Mint(address indexed to, uint256 amount);
    
    function initialize(address owner, address dataFeed_gold_address, address dataFeed_eth_address) public initializer {
        __ERC20_init("Gold", "GLD");
        __ERC20Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(OWNER_ROLE, owner);

        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);

        dataFeed_gold = AggregatorV3Interface(
            dataFeed_gold_address // 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea
        );
        dataFeed_eth = AggregatorV3Interface(
            dataFeed_eth_address // 0x694AA1769357215DE4FAC081bf1f309aDC325306
        );

        fees = 5; // 5%
        feesAddress = owner;
    }

    constructor () initializer {}

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
        require(msg.value > 0, "GoldToken: mint value must be greater than 0");
        int goldPriceInEth = getGoldPriceInEth() * 10**10; // 10**8 + 10**10 = 10**18
        uint256 goldAmount = msg.value * 10**18 / uint256(goldPriceInEth);
        require(goldAmount > 0, "GoldToken: gold amount must be greater than 0");
        uint256 fee = goldAmount * fees / 100;
        goldAmount -= fee;
        _mint(msg.sender, goldAmount);
        _mint(feesAddress, fee);
        emit Mint(msg.sender, goldAmount);
    }

    function burn(uint256 amount) external whenNotPaused {
        _burn(msg.sender, amount);
    }

    function getGoldPriceInEth() internal view returns (int) {
        (,int gold_usd,,,) = dataFeed_gold.latestRoundData(); // 1 gold = x USD
        (,int eth_usd,,,) = dataFeed_eth.latestRoundData(); // 1 ETH = y USD
        return gold_usd * 10**8 / eth_usd; // 1 gold = (gold_usd / eth_usd) ETH
    }

    function getFees() external view returns (uint256) {
        return fees;
    }
    
    function getFeesAddress() external view returns (address) {
        return feesAddress;
    }

    function hasOwnerRole(address account) external view returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }

    function setFeesAddress(address _feesAddress) external onlyRole(OWNER_ROLE) { // Lotterie contract
        feesAddress = _feesAddress;
    }

    function claimEth() external onlyRole(OWNER_ROLE) {
        payable(msg.sender).transfer(address(this).balance);
    }
}