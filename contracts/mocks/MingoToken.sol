// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MingoToken is ERC20 {
    constructor() ERC20("Mingo Token", "MINGO") {
        _mint(msg.sender, 1000000000 * 10**decimals());
    }

    function mint(address _address) external {
        _mint(_address, 1000000000 * 10**decimals());
    }
}
