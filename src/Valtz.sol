// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import {IValtzPool} from "./ValtzPool.sol";
import {VALTZ_SIGNER_ROLE as _VALTZ_SIGNER_ROLE} from "./ValtzConstants.sol";
import "./ValtzEvents.sol";

import {ValtzAttestation} from "./lib/ValtzAttestation.sol";

contract Valtz is AccessControl {
    address public poolImplementation;
    bytes32 public constant VALTZ_SIGNER_ROLE = _VALTZ_SIGNER_ROLE;
    bytes32 public constant POOL_CREATOR_ADMIN_ROLE = keccak256("POOL_CREATOR_ADMIN_ROLE");

    constructor(address defaultAdmin, address _poolImplementation) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        poolImplementation = _poolImplementation;
    }

    /**
     * @dev Permissionlessly a new pool with the given configuration.
     *         Note that this will be removed in production.
     * @param config The configuration of the pool.
     * @return pool The address of the new pool.
     */
    function createPool(IValtzPool.PoolConfig memory config) external returns (address pool) {
        return _createPool(config);
    }

    function adminCreatePool(IValtzPool.PoolConfig memory config)
        external
        onlyRole(POOL_CREATOR_ADMIN_ROLE)
    {
        _createPool(config);
    }

    function subnetOwnerCreatePool(IValtzPool.PoolConfig memory config) external {
        // TODO - Add the logic to check if the caller is the owner of the subnet
        _createPool(config);
    }

    function _createPool(IValtzPool.PoolConfig memory config) internal returns (address pool) {
        pool = Clones.clone(poolImplementation);
        IValtzPool(pool).initialize(config);
        emit CreatePool(pool);
    }
}
