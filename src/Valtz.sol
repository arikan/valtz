// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import {IValtzPool} from "./ValtzPool.sol";

contract Valtz is AccessControl {
    event CreatePool(address pool);

    address poolImplementation;

    constructor(address defaultAdmin, address _poolImplementation) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        poolImplementation = _poolImplementation;
    }

    function createPool(IValtzPool.PoolConfig memory config) external returns (address) {
        address pool = Clones.clone(poolImplementation);
        IValtzPool(pool).initialize(config);
        emit CreatePool(pool);
        return pool;
    }
}
