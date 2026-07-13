// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { BastionTypes } from "../types/BastionTypes.sol";

contract VaultLedger is BastionAccessControl {
    error UnknownVault();
    error UnknownCollateral();
    error VaultNotActive();
    error VaultNotLiquidating();
    error NotVaultOwner();
    error CollateralAlreadyListed();
    error CollateralNotEnabled();
    error InvalidAmount();

    uint256 public nextVaultId = 1;

    mapping(uint256 vaultId => BastionTypes.Vault vault) private _vaults;
    mapping(address owner => uint256[] vaultIds) private _ownerVaults;
    mapping(address collateral => BastionTypes.CollateralConfig config) private _collateralConfigs;
    mapping(address collateral => bool listed) private _listed;

    address[] private _collateralList;

    event CollateralListed(address indexed collateral, address indexed oracle, string symbol);
    event CollateralUpdated(address indexed collateral, address indexed oracle, bool enabled);
    event VaultCreated(uint256 indexed vaultId, address indexed owner, address indexed collateral);
    event VaultDebtUpdated(uint256 indexed vaultId, uint256 previousDebt, uint256 newDebt);
    event VaultCollateralUpdated(
        uint256 indexed vaultId, uint256 previousAmount, uint256 newAmount
    );
    event VaultFeeIndexUpdated(uint256 indexed vaultId, uint256 previousIndex, uint256 newIndex);
    event VaultStatusUpdated(uint256 indexed vaultId, BastionTypes.VaultStatus status);

    constructor(
        address initialOwner
    ) BastionAccessControl(initialOwner) { }

    function listCollateral(
        BastionTypes.CollateralConfig calldata config
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        if (_listed[config.token]) revert CollateralAlreadyListed();
        _listed[config.token] = true;
        _collateralList.push(config.token);
        _collateralConfigs[config.token] = config;
        emit CollateralListed(config.token, config.oracle, config.symbol);
    }

    function updateCollateral(
        BastionTypes.CollateralConfig calldata config
    ) external onlyRole(BastionRoles.RISK_MANAGER_ROLE) {
        if (!_listed[config.token]) revert UnknownCollateral();
        _collateralConfigs[config.token] = config;
        emit CollateralUpdated(config.token, config.oracle, config.enabled);
    }

    function createVault(
        address owner_,
        address collateralToken,
        uint256 feeIndex
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) returns (uint256 vaultId) {
        BastionTypes.CollateralConfig memory config = _collateralConfigs[collateralToken];
        if (!_listed[collateralToken]) revert UnknownCollateral();
        if (!config.enabled) revert CollateralNotEnabled();

        vaultId = nextVaultId++;
        _vaults[vaultId] = BastionTypes.Vault({
            id: vaultId,
            owner: owner_,
            collateralToken: collateralToken,
            collateralAmount: 0,
            debt: 0,
            feeIndex: feeIndex,
            openedAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp),
            status: BastionTypes.VaultStatus.Active
        });

        _ownerVaults[owner_].push(vaultId);
        emit VaultCreated(vaultId, owner_, collateralToken);
    }

    function increaseCollateral(
        uint256 vaultId,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        if (amount == 0) revert InvalidAmount();
        BastionTypes.Vault storage vault = _requireActive(vaultId);
        uint256 previous = vault.collateralAmount;
        vault.collateralAmount = previous + amount;
        vault.updatedAt = uint64(block.timestamp);
        emit VaultCollateralUpdated(vaultId, previous, vault.collateralAmount);
    }

    function decreaseCollateral(
        uint256 vaultId,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        if (amount == 0) revert InvalidAmount();
        BastionTypes.Vault storage vault = _requireActive(vaultId);
        uint256 previous = vault.collateralAmount;
        if (amount > previous) revert InvalidAmount();
        vault.collateralAmount = previous - amount;
        vault.updatedAt = uint64(block.timestamp);
        emit VaultCollateralUpdated(vaultId, previous, vault.collateralAmount);
    }

    function setCollateralAmount(
        uint256 vaultId,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        BastionTypes.Vault storage vault = _requireExisting(vaultId);
        uint256 previous = vault.collateralAmount;
        vault.collateralAmount = amount;
        vault.updatedAt = uint64(block.timestamp);
        emit VaultCollateralUpdated(vaultId, previous, amount);
    }

    function increaseDebt(
        uint256 vaultId,
        uint256 amount
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        if (amount == 0) revert InvalidAmount();
        BastionTypes.Vault storage vault = _requireActive(vaultId);
        uint256 previous = vault.debt;
        vault.debt = previous + amount;
        vault.updatedAt = uint64(block.timestamp);
        emit VaultDebtUpdated(vaultId, previous, vault.debt);
    }

    function setDebt(
        uint256 vaultId,
        uint256 newDebt
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        BastionTypes.Vault storage vault = _requireExisting(vaultId);
        uint256 previous = vault.debt;
        vault.debt = newDebt;
        vault.updatedAt = uint64(block.timestamp);
        emit VaultDebtUpdated(vaultId, previous, newDebt);
    }

    function setFeeIndex(
        uint256 vaultId,
        uint256 newIndex
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        BastionTypes.Vault storage vault = _requireExisting(vaultId);
        uint256 previous = vault.feeIndex;
        vault.feeIndex = newIndex;
        vault.updatedAt = uint64(block.timestamp);
        emit VaultFeeIndexUpdated(vaultId, previous, newIndex);
    }

    function setStatus(
        uint256 vaultId,
        BastionTypes.VaultStatus status
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        BastionTypes.Vault storage vault = _requireExisting(vaultId);
        vault.status = status;
        vault.updatedAt = uint64(block.timestamp);
        emit VaultStatusUpdated(vaultId, status);
    }

    function closeVault(
        uint256 vaultId,
        uint256 feeIndex
    ) external onlyRole(BastionRoles.PROTOCOL_ROLE) {
        BastionTypes.Vault storage vault = _requireExisting(vaultId);
        vault.debt = 0;
        vault.feeIndex = feeIndex;
        vault.status = BastionTypes.VaultStatus.Closed;
        vault.updatedAt = uint64(block.timestamp);
        emit VaultDebtUpdated(vaultId, vault.debt, 0);
        emit VaultStatusUpdated(vaultId, BastionTypes.VaultStatus.Closed);
    }

    function requireVaultOwner(
        uint256 vaultId,
        address owner_
    ) external view {
        BastionTypes.Vault memory vault = _vaults[vaultId];
        if (vault.id == 0) revert UnknownVault();
        if (vault.owner != owner_) revert NotVaultOwner();
    }

    function requireActive(
        uint256 vaultId
    ) external view {
        _requireActive(vaultId);
    }

    function requireLiquidating(
        uint256 vaultId
    ) external view {
        BastionTypes.Vault memory vault = _vaults[vaultId];
        if (vault.id == 0) revert UnknownVault();
        if (vault.status != BastionTypes.VaultStatus.Liquidating) revert VaultNotLiquidating();
    }

    function getVault(
        uint256 vaultId
    ) public view returns (BastionTypes.Vault memory) {
        BastionTypes.Vault memory vault = _vaults[vaultId];
        if (vault.id == 0) revert UnknownVault();
        return vault;
    }

    function collateralConfig(
        address collateralToken
    ) public view returns (BastionTypes.CollateralConfig memory) {
        if (!_listed[collateralToken]) revert UnknownCollateral();
        return _collateralConfigs[collateralToken];
    }

    function isCollateralListed(
        address collateralToken
    ) external view returns (bool) {
        return _listed[collateralToken];
    }

    function collateralCount() external view returns (uint256) {
        return _collateralList.length;
    }

    function collateralAt(
        uint256 index
    ) external view returns (address) {
        return _collateralList[index];
    }

    function vaultsOf(
        address owner_
    ) external view returns (uint256[] memory) {
        return _ownerVaults[owner_];
    }

    function _requireExisting(
        uint256 vaultId
    ) internal view returns (BastionTypes.Vault storage vault) {
        vault = _vaults[vaultId];
        if (vault.id == 0) revert UnknownVault();
    }

    function _requireActive(
        uint256 vaultId
    ) internal view returns (BastionTypes.Vault storage vault) {
        vault = _vaults[vaultId];
        if (vault.id == 0) revert UnknownVault();
        if (vault.status != BastionTypes.VaultStatus.Active) revert VaultNotActive();
    }
}
