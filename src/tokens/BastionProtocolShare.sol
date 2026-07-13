// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { BastionERC20 } from "./BastionERC20.sol";

contract BastionProtocolShare is BastionERC20, BastionAccessControl {
    event SharesIssued(address indexed receiver, uint256 amount, address indexed issuer);

    constructor(
        address initialOwner
    )
        BastionERC20("Bastion Recapitalization Share", "BRS", 18)
        BastionAccessControl(initialOwner)
    { }

    function mint(
        address to,
        uint256 amount
    ) external onlyRole(BastionRoles.TOKEN_MINTER_ROLE) {
        _mint(to, amount);
        emit SharesIssued(to, amount, msg.sender);
    }
}
