// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface IStarknetERC20Bridge {

    function deposit(uint256 amount, uint256 l2Recipient) external;
    function withdraw(uint256 amount, address recipient) external;
}