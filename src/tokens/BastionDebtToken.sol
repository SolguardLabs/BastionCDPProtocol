// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { BastionERC20 } from "./BastionERC20.sol";

contract BastionDebtToken is BastionERC20, BastionAccessControl {
    event DebtMinted(address indexed to, uint256 amount, address indexed operator);
    event DebtBurned(address indexed from, uint256 amount, address indexed operator);

    constructor(
        address initialOwner
    ) BastionERC20("Bastion Dollar", "bUSD", 18) BastionAccessControl(initialOwner) { }

    function mint(
        address to,
        uint256 amount
    ) external onlyRole(BastionRoles.TOKEN_MINTER_ROLE) {
        _mint(to, amount);
        emit DebtMinted(to, amount, msg.sender);
    }

    function burn(
        address from,
        uint256 amount
    ) external onlyRole(BastionRoles.TOKEN_BURNER_ROLE) {
        _burn(from, amount);
        emit DebtBurned(from, amount, msg.sender);
    }

    function burnFrom(
        address from,
        uint256 amount
    ) external onlyRole(BastionRoles.TOKEN_BURNER_ROLE) {
        _burn(from, amount);
        emit DebtBurned(from, amount, msg.sender);
    }
}
