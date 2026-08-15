// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { RiskParameterTimelock } from "../../src/governance/RiskParameterTimelock.sol";
import { Test } from "forge-std/Test.sol";

contract TimelockParameterTarget {
    error Unauthorized();

    address public immutable controller;
    uint256 public value;

    constructor(
        address controller_
    ) {
        controller = controller_;
    }

    function setValue(
        uint256 value_
    ) external returns (uint256) {
        if (msg.sender != controller) revert Unauthorized();
        value = value_;
        return value_;
    }
}

contract RiskParameterTimelockTest is Test {
    RiskParameterTimelock internal timelock;
    TimelockParameterTarget internal target;

    uint64 internal constant DELAY = 2 days;
    uint64 internal constant GRACE = 7 days;

    function setUp() public {
        timelock = new RiskParameterTimelock(address(this), DELAY, GRACE);
        target = new TimelockParameterTarget(address(timelock));
    }

    function testExecutesScheduledParameterChangeAfterDelay() public {
        bytes memory data = abi.encodeCall(target.setValue, (42));
        bytes32 salt = keccak256("risk-epoch-42");
        bytes32 operationId = timelock.schedule(address(target), 0, data, 0, salt, DELAY);

        assertEq(
            uint256(timelock.stateOf(operationId)),
            uint256(RiskParameterTimelock.OperationState.Waiting)
        );

        vm.expectRevert(RiskParameterTimelock.OperationNotReady.selector);
        timelock.execute(address(target), 0, data, 0, salt);

        vm.warp(block.timestamp + DELAY);
        bytes memory result = timelock.execute(address(target), 0, data, 0, salt);

        assertEq(abi.decode(result, (uint256)), 42);
        assertEq(target.value(), 42);
        assertEq(
            uint256(timelock.stateOf(operationId)),
            uint256(RiskParameterTimelock.OperationState.Executed)
        );

        vm.expectRevert(RiskParameterTimelock.OperationAlreadyFinalized.selector);
        timelock.execute(address(target), 0, data, 0, salt);
    }

    function testGuardianCanCancelPendingChange() public {
        bytes memory data = abi.encodeCall(target.setValue, (7));
        bytes32 salt = keccak256("cancelled-risk-epoch");
        bytes32 operationId = timelock.schedule(address(target), 0, data, 0, salt, DELAY);

        timelock.cancel(operationId);

        assertEq(
            uint256(timelock.stateOf(operationId)),
            uint256(RiskParameterTimelock.OperationState.Cancelled)
        );
        vm.warp(block.timestamp + DELAY);
        vm.expectRevert(RiskParameterTimelock.OperationAlreadyFinalized.selector);
        timelock.execute(address(target), 0, data, 0, salt);
    }

    function testPredecessorMustExecuteFirst() public {
        bytes memory firstData = abi.encodeCall(target.setValue, (11));
        bytes memory secondData = abi.encodeCall(target.setValue, (12));
        bytes32 firstSalt = keccak256("first");
        bytes32 secondSalt = keccak256("second");

        bytes32 firstId = timelock.schedule(address(target), 0, firstData, 0, firstSalt, DELAY);
        timelock.schedule(address(target), 0, secondData, firstId, secondSalt, DELAY);
        vm.warp(block.timestamp + DELAY);

        vm.expectRevert(RiskParameterTimelock.MissingPredecessor.selector);
        timelock.execute(address(target), 0, secondData, firstId, secondSalt);

        timelock.execute(address(target), 0, firstData, 0, firstSalt);
        timelock.execute(address(target), 0, secondData, firstId, secondSalt);
        assertEq(target.value(), 12);
    }

    function testExpiredOperationCannotExecute() public {
        bytes memory data = abi.encodeCall(target.setValue, (99));
        bytes32 salt = keccak256("expired");
        bytes32 operationId = timelock.schedule(address(target), 0, data, 0, salt, DELAY);

        vm.warp(block.timestamp + DELAY + GRACE + 1);

        assertEq(
            uint256(timelock.stateOf(operationId)),
            uint256(RiskParameterTimelock.OperationState.Expired)
        );
        vm.expectRevert(RiskParameterTimelock.OperationExpired.selector);
        timelock.execute(address(target), 0, data, 0, salt);
    }

    function testTimingCanOnlyChangeThroughTimelock() public {
        vm.expectRevert(RiskParameterTimelock.OnlySelf.selector);
        timelock.updateTiming(3 days, 10 days);

        bytes memory data = abi.encodeCall(timelock.updateTiming, (3 days, 10 days));
        bytes32 salt = keccak256("timing-v2");
        timelock.schedule(address(timelock), 0, data, 0, salt, DELAY);
        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(timelock), 0, data, 0, salt);

        assertEq(timelock.minimumDelay(), 3 days);
        assertEq(timelock.gracePeriod(), 10 days);
    }

    function testCalldataMutationCannotUseExistingSchedule() public {
        bytes memory approvedData = abi.encodeCall(target.setValue, (10));
        bytes memory mutatedData = abi.encodeCall(target.setValue, (1000));
        bytes32 salt = keccak256("calldata-bound");
        timelock.schedule(address(target), 0, approvedData, 0, salt, DELAY);
        vm.warp(block.timestamp + DELAY);

        vm.expectRevert(RiskParameterTimelock.OperationUnknown.selector);
        timelock.execute(address(target), 0, mutatedData, 0, salt);
        assertEq(target.value(), 0);
    }

    function testRejectsDelayBelowMinimum() public {
        bytes memory data = abi.encodeCall(target.setValue, (1));
        vm.expectRevert(RiskParameterTimelock.InvalidTiming.selector);
        timelock.schedule(address(target), 0, data, 0, bytes32(uint256(1)), DELAY - 1);
    }
}
