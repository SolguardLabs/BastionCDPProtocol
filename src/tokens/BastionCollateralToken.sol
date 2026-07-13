// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { BastionERC20 } from "./BastionERC20.sol";

contract BastionCollateralToken is BastionERC20, BastionAccessControl {
    uint256 public immutable faucetAmount;
    mapping(address account => uint256 timestamp) public lastFaucet;

    event FaucetClaimed(address indexed account, uint256 amount);

    constructor(
        address initialOwner,
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialSupply,
        uint256 faucetDrip
    ) BastionERC20(tokenName, tokenSymbol, 18) BastionAccessControl(initialOwner) {
        faucetAmount = faucetDrip;
        if (initialSupply != 0) {
            _mint(initialOwner, initialSupply);
        }
    }

    function mint(
        address to,
        uint256 amount
    ) external onlyRole(BastionRoles.TOKEN_MINTER_ROLE) {
        _mint(to, amount);
    }

    function faucet() external {
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp >= lastFaucet[msg.sender] + 1 days, "BASTION_FAUCET_COOLDOWN");
        lastFaucet[msg.sender] = block.timestamp;
        _mint(msg.sender, faucetAmount);
        emit FaucetClaimed(msg.sender, faucetAmount);
    }
}
