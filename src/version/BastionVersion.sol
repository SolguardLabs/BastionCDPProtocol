// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract BastionVersion {
    string public constant PROTOCOL = "BastionCDPProtocol";
    string public constant VERSION = "1.0.0";
    string public constant SCHEMA_VERSION = "bastion-cdp/v1";

    function release()
        external
        pure
        returns (string memory protocol, string memory version, string memory schemaVersion)
    {
        return (PROTOCOL, VERSION, SCHEMA_VERSION);
    }
}
