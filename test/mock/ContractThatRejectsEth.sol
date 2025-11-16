// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract ContractThatRejectsEth {
    receive() external payable {
        revert("I reject ETH");
    }
}