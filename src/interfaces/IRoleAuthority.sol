// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRoleAuthority {
    function hasRole(bytes32 role, address account) external view returns (bool);
}
