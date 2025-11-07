// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IGoldToken
 * @notice Interface for the Gold Token contract
 */
interface IGoldToken {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Mint(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ValueMustBeGreaterThanZero();
    error AmountMustBeGreaterThanZero();
    error InvalidGoldPrice();

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function addOwner(address account) external;
    function removeOwner(address account) external;
    function pause() external;
    function unpause() external;
    function setFeesAddress(address feesAddress) external;
    function setLotterieAddress(address lotterieAddress) external;
    function claimEth() external;

    /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address owner, 
        address dataFeedGoldAddress, 
        address dataFeedEthAddress
    ) external;

    function mint() external payable;
    function burn(uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getFees() external view returns (uint256);
    function getFeesAddress() external view returns (address);
    function getUsers() external view returns (address[] memory);
    function getTimestamps() external view returns (address[] memory, uint256[] memory);
    function hasOwnerRole(address account) external view returns (bool);
    function getGoldPriceInEth() external view returns (int256);
    function balanceOf(address account) external view returns (uint256);
}
