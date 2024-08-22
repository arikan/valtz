// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import {IValtzPool} from "./ValtzPool.sol";
import {VALTZ_SIGNER_ROLE as _VALTZ_SIGNER_ROLE} from "./ValtzConstants.sol";
import "./ValtzEvents.sol";

contract Valtz is AccessControl {
    address public poolImplementation;
    bytes32 public constant VALTZ_SIGNER_ROLE = _VALTZ_SIGNER_ROLE;

    constructor(address defaultAdmin, address _poolImplementation) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        poolImplementation = _poolImplementation;
    }

    function createPool(IValtzPool.PoolConfig memory config) external returns (address pool) {
        pool = Clones.clone(poolImplementation);
        IValtzPool(pool).initialize(config);
        emit CreatePool(pool);
    }
}
