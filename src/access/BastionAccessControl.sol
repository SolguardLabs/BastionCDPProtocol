// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library BastionRoles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PROTOCOL_ROLE = keccak256("BASTION_PROTOCOL_ROLE");
    bytes32 internal constant RISK_MANAGER_ROLE = keccak256("BASTION_RISK_MANAGER_ROLE");
    bytes32 internal constant AUCTIONEER_ROLE = keccak256("BASTION_AUCTIONEER_ROLE");
    bytes32 internal constant TOKEN_MINTER_ROLE = keccak256("BASTION_TOKEN_MINTER_ROLE");
    bytes32 internal constant TOKEN_BURNER_ROLE = keccak256("BASTION_TOKEN_BURNER_ROLE");
    bytes32 internal constant ORACLE_POSTER_ROLE = keccak256("BASTION_ORACLE_POSTER_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("BASTION_PAUSER_ROLE");
}

contract BastionAccessControl {
    error ZeroAddress();
    error MissingRole(bytes32 role, address account);
    error OwnerUnchanged();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    address private _owner;
    mapping(bytes32 role => mapping(address account => bool enabled)) private _roles;

    constructor(
        address initialOwner
    ) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _owner = initialOwner;
        _roles[BastionRoles.DEFAULT_ADMIN_ROLE][initialOwner] = true;
        emit OwnershipTransferred(address(0), initialOwner);
        emit RoleGranted(BastionRoles.DEFAULT_ADMIN_ROLE, initialOwner, initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert MissingRole(BastionRoles.DEFAULT_ADMIN_ROLE, msg.sender);
        _;
    }

    modifier onlyRole(
        bytes32 role
    ) {
        _checkRole(role, msg.sender);
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function hasRole(
        bytes32 role,
        address account
    ) public view returns (bool) {
        return _roles[role][account] || _roles[BastionRoles.DEFAULT_ADMIN_ROLE][account];
    }

    function transferOwnership(
        address newOwner
    ) external onlyOwner {
        _transferOwnership(newOwner);
    }

    function grantRole(
        bytes32 role,
        address account
    ) external onlyRole(BastionRoles.DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(
        bytes32 role,
        address account
    ) external onlyRole(BastionRoles.DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function renounceRole(
        bytes32 role
    ) external {
        _revokeRole(role, msg.sender);
    }

    function _checkRole(
        bytes32 role,
        address account
    ) internal view {
        if (!hasRole(role, account)) revert MissingRole(role, account);
    }

    function _grantRole(
        bytes32 role,
        address account
    ) internal {
        if (account == address(0)) revert ZeroAddress();
        if (_roles[role][account]) return;
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function _revokeRole(
        bytes32 role,
        address account
    ) internal {
        if (!_roles[role][account]) return;
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function _transferOwnership(
        address newOwner
    ) internal {
        if (newOwner == address(0)) revert ZeroAddress();
        if (newOwner == _owner) revert OwnerUnchanged();

        address previous = _owner;
        _owner = newOwner;
        _roles[BastionRoles.DEFAULT_ADMIN_ROLE][newOwner] = true;
        emit OwnershipTransferred(previous, newOwner);
        emit RoleGranted(BastionRoles.DEFAULT_ADMIN_ROLE, newOwner, msg.sender);
    }
}
