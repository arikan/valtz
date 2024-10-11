// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import {IValtzPool} from "./ValtzPool.sol";
import {ValtzEvents} from "./lib/Events.sol";
import {VALTZ_SIGNER_ROLE as _VALTZ_SIGNER_ROLE} from "./ValtzConstants.sol";

contract Valtz is AccessControl {
    address public immutable poolImplementation;
    bytes32 public constant VALTZ_SIGNER_ROLE = _VALTZ_SIGNER_ROLE;
    bytes32 public constant POOL_CREATOR_ADMIN_ROLE = keccak256("POOL_CREATOR_ADMIN_ROLE");

    /**
     * @dev Constructor for Valtz contract.
     * @param defaultAdmin The address of the default admin.
     * @param _poolImplementation The address of the pool implementation contract.
     */
    constructor(address defaultAdmin, address _poolImplementation) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        poolImplementation = _poolImplementation;
    }

    /**
     * @dev Permissionlessly create a new pool with the given configuration.
     *      Note that this will be removed in production.
     * @param config The configuration of the pool.
     * @return pool The address of the new pool.
     */
    function createPool(IValtzPool.PoolConfig memory config) external returns (address pool) {
        return _createPool(config);
    }

    /**
     * @dev Internal function to create a new pool.
     * @param config The configuration of the pool.
     * @return pool The address of the new pool.
     */
    function _createPool(IValtzPool.PoolConfig memory config) internal returns (address pool) {
        pool = Clones.clone(poolImplementation);
        IValtzPool(pool).initialize(config);
        emit ValtzEvents.CreatePool(pool);
    }
}
