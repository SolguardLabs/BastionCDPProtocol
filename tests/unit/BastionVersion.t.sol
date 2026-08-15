// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BastionVersion } from "../../src/version/BastionVersion.sol";
import { Test } from "forge-std/Test.sol";

contract BastionVersionTest is Test {
    function testReleaseMetadata() public {
        BastionVersion version = new BastionVersion();
        (string memory protocol, string memory release, string memory schema) = version.release();

        assertEq(protocol, "BastionCDPProtocol");
        assertEq(release, "1.0.0");
        assertEq(schema, "bastion-cdp/v1");
    }
}
