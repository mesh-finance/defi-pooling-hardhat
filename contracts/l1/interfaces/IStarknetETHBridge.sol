// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface IStarknetETHBridge {

    function deposit(uint256 l2Recipient) external payable;
    function withdraw(uint256 amount, address recipient) external;
}