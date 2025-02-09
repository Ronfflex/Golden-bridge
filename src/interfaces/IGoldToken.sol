// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IGoldToken {
    function addOwner(address account) external;
    function removeOwner(address account) external;
    function pause() external;
    function unpause() external;
    function mint() external;
    function burn(uint256 amount) external;
    function transfer(address to, uint256 amount) external;
    function getFees() external view returns (uint256);
    function getFeesAddress() external view returns (address);
    function getUsers() external view returns (address[] memory);
    function getTimestamps() external view returns (address[] memory, uint256[] memory);
    function hasOwnerRole(address account) external view returns (bool);
    function setFeesAddress(address feesAddress) external;
    function claimEth() external;
    function balanceOf(address account) external view returns (uint256);
}
