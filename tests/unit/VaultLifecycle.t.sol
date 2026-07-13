// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionTypes } from "../../src/types/BastionTypes.sol";
import { BastionTestBase } from "../helpers/BastionTestBase.sol";

contract VaultLifecycleTest is BastionTestBase {
    function testVaultCreationAndDeposit() public {
        uint256 vaultId = openDepositOnly(alice, 10e18);

        BastionTypes.Vault memory data = protocol.vault(vaultId);

        assertEq(data.owner, alice);
        assertEq(data.collateralToken, address(collateral));
        assertEq(data.collateralAmount, 10e18);
        assertEq(data.debt, 0);
        assertEq(uint256(data.status), uint256(BastionTypes.VaultStatus.Active));
        assertEq(collateral.balanceOf(address(protocol)), 10e18);
    }

    function testMintDebtAgainstCollateral() public {
        uint256 vaultId = openDepositAndMint(alice, 10e18, 5000e18);

        BastionTypes.Vault memory data = protocol.vault(vaultId);

        assertEq(data.debt, 5000e18);
        assertEq(debt.balanceOf(alice), 5000e18);
        assertEq(protocol.accounting().normalizedDebtByCollateral(address(collateral)), 5000e18);
    }

    function testRepayDebtInTwoSteps() public {
        uint256 vaultId = openDepositAndMint(alice, 10e18, 3000e18);

        vm.prank(alice);
        protocol.repayDebt(vaultId, 1000e18);

        assertVaultDebt(vaultId, 2000e18);
        assertEq(debt.balanceOf(alice), 2000e18);

        vm.prank(alice);
        protocol.repayDebt(vaultId, 2000e18);

        assertVaultDebt(vaultId, 0);
        assertEq(debt.balanceOf(alice), 0);
    }

    function testWithdrawAfterDebtIsCleared() public {
        uint256 vaultId = openDepositAndMint(alice, 10e18, 3000e18);

        vm.prank(alice);
        protocol.repayDebt(vaultId, 3000e18);

        uint256 beforeBalance = collateral.balanceOf(alice);

        vm.prank(alice);
        protocol.withdrawCollateral(vaultId, 10e18, alice);

        BastionTypes.Vault memory data = protocol.vault(vaultId);

        assertEq(collateral.balanceOf(alice), beforeBalance + 10e18);
        assertEq(data.collateralAmount, 0);
        assertEq(uint256(data.status), uint256(BastionTypes.VaultStatus.Closed));
    }

    function testPartialWithdrawKeepsVaultHealthy() public {
        uint256 vaultId = openDepositAndMint(alice, 10e18, 5000e18);

        vm.prank(alice);
        protocol.withdrawCollateral(vaultId, 2e18, alice);

        BastionTypes.Vault memory data = protocol.vault(vaultId);

        assertEq(data.collateralAmount, 8e18);
        assertEq(data.debt, 5000e18);
        assertEq(collateral.balanceOf(address(protocol)), 8e18);
    }
}
