// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionAccessControl, BastionRoles } from "../access/BastionAccessControl.sol";
import { BastionReentrancyGuard } from "../core/BastionReentrancyGuard.sol";

contract RiskParameterTimelock is BastionAccessControl, BastionReentrancyGuard {
    error InvalidTiming();
    error InvalidTarget();
    error OperationAlreadyScheduled();
    error OperationUnknown();
    error OperationNotReady();
    error OperationExpired();
    error OperationAlreadyFinalized();
    error MissingPredecessor();
    error ExecutionFailed(bytes returnData);
    error OnlySelf();

    enum OperationState {
        Unset,
        Waiting,
        Ready,
        Executed,
        Cancelled,
        Expired
    }

    struct Operation {
        address target;
        uint96 value;
        uint64 proposedAt;
        uint64 readyAt;
        uint64 expiresAt;
        address proposer;
        bytes32 predecessor;
        bytes32 dataHash;
        bool executed;
        bool cancelled;
    }

    bytes32 public constant DOMAIN = keccak256("BASTION_RISK_TIMELOCK_V1");
    uint64 public minimumDelay;
    uint64 public gracePeriod;

    mapping(bytes32 operationId => Operation operation) private _operations;
    bytes32[] private _operationIds;

    event OperationScheduled(
        bytes32 indexed operationId,
        address indexed target,
        address indexed proposer,
        uint256 value,
        bytes32 dataHash,
        bytes32 predecessor,
        uint64 readyAt,
        uint64 expiresAt
    );
    event OperationExecuted(
        bytes32 indexed operationId, address indexed target, address indexed executor
    );
    event OperationCancelled(bytes32 indexed operationId, address indexed guardian);
    event TimingUpdated(
        uint64 previousDelay, uint64 newDelay, uint64 previousGrace, uint64 newGrace
    );

    constructor(
        address initialAdmin,
        uint64 minimumDelay_,
        uint64 gracePeriod_
    ) BastionAccessControl(initialAdmin) {
        _validateTiming(minimumDelay_, gracePeriod_);
        minimumDelay = minimumDelay_;
        gracePeriod = gracePeriod_;

        _grantRole(BastionRoles.GOVERNOR_ROLE, initialAdmin);
        _grantRole(BastionRoles.EXECUTOR_ROLE, initialAdmin);
        _grantRole(BastionRoles.GUARDIAN_ROLE, initialAdmin);
    }

    receive() external payable { }

    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN,
                block.chainid,
                address(this),
                target,
                value,
                keccak256(data),
                predecessor,
                salt
            )
        );
    }

    function schedule(
        address target,
        uint96 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint64 delay
    ) external onlyRole(BastionRoles.GOVERNOR_ROLE) returns (bytes32 operationId) {
        if (target == address(0)) revert InvalidTarget();
        if (delay < minimumDelay) revert InvalidTiming();

        operationId = hashOperation(target, value, data, predecessor, salt);
        if (_operations[operationId].proposedAt != 0) revert OperationAlreadyScheduled();

        uint64 readyAt = uint64(block.timestamp) + delay;
        uint64 expiresAt = readyAt + gracePeriod;
        _operations[operationId] = Operation({
            target: target,
            value: value,
            proposedAt: uint64(block.timestamp),
            readyAt: readyAt,
            expiresAt: expiresAt,
            proposer: msg.sender,
            predecessor: predecessor,
            dataHash: keccak256(data),
            executed: false,
            cancelled: false
        });
        _operationIds.push(operationId);

        emit OperationScheduled(
            operationId, target, msg.sender, value, keccak256(data), predecessor, readyAt, expiresAt
        );
    }

    function execute(
        address target,
        uint96 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external nonReentrant onlyRole(BastionRoles.EXECUTOR_ROLE) returns (bytes memory result) {
        bytes32 operationId = hashOperation(target, value, data, predecessor, salt);
        Operation storage operation = _requireOperation(operationId);

        if (operation.executed || operation.cancelled) revert OperationAlreadyFinalized();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < operation.readyAt) revert OperationNotReady();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > operation.expiresAt) revert OperationExpired();
        if (predecessor != bytes32(0) && !_operations[predecessor].executed) {
            revert MissingPredecessor();
        }
        if (operation.target != target || operation.value != value) revert InvalidTarget();
        if (operation.dataHash != keccak256(data) || operation.predecessor != predecessor) {
            revert InvalidTarget();
        }

        operation.executed = true;
        (bool success, bytes memory returnData) = target.call{ value: value }(data);
        if (!success) revert ExecutionFailed(returnData);

        emit OperationExecuted(operationId, target, msg.sender);
        return returnData;
    }

    function cancel(
        bytes32 operationId
    ) external onlyRole(BastionRoles.GUARDIAN_ROLE) {
        Operation storage operation = _requireOperation(operationId);
        if (operation.executed || operation.cancelled) revert OperationAlreadyFinalized();
        operation.cancelled = true;
        emit OperationCancelled(operationId, msg.sender);
    }

    function updateTiming(
        uint64 newMinimumDelay,
        uint64 newGracePeriod
    ) external {
        if (msg.sender != address(this)) revert OnlySelf();
        _validateTiming(newMinimumDelay, newGracePeriod);

        uint64 previousDelay = minimumDelay;
        uint64 previousGrace = gracePeriod;
        minimumDelay = newMinimumDelay;
        gracePeriod = newGracePeriod;

        emit TimingUpdated(previousDelay, newMinimumDelay, previousGrace, newGracePeriod);
    }

    function stateOf(
        bytes32 operationId
    ) public view returns (OperationState) {
        Operation memory operation = _operations[operationId];
        if (operation.proposedAt == 0) return OperationState.Unset;
        if (operation.executed) return OperationState.Executed;
        if (operation.cancelled) return OperationState.Cancelled;
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > operation.expiresAt) return OperationState.Expired;
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= operation.readyAt) return OperationState.Ready;
        return OperationState.Waiting;
    }

    function getOperation(
        bytes32 operationId
    ) external view returns (Operation memory) {
        return _requireOperation(operationId);
    }

    function operationCount() external view returns (uint256) {
        return _operationIds.length;
    }

    function operationIdAt(
        uint256 index
    ) external view returns (bytes32) {
        return _operationIds[index];
    }

    function isExecuted(
        bytes32 operationId
    ) external view returns (bool) {
        return _operations[operationId].executed;
    }

    function _requireOperation(
        bytes32 operationId
    ) internal view returns (Operation storage operation) {
        operation = _operations[operationId];
        if (operation.proposedAt == 0) revert OperationUnknown();
    }

    function _validateTiming(
        uint64 delay,
        uint64 grace
    ) internal pure {
        if (delay < 1 hours || delay > 30 days) revert InvalidTiming();
        if (grace < 1 days || grace > 30 days) revert InvalidTiming();
    }
}
