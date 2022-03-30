//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(uint256 amount) ERC20("BearingToken", "bear") {
        _mint(_msgSender(), amount);
    }

    function removeTokens(uint256 amount, address guy) external {
        _burn(guy, amount);
    }
}
