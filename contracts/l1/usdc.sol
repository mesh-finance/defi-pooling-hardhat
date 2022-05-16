pragma solidity 0.7.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20 {
    constructor () ERC20('USDC', 'USDC') {
        _mint(msg.sender, 1_000_000 * 1 ether);
    }
}
