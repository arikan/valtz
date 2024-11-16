// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import {IValtzPool} from "./ValtzPool.sol";
import {VALTZ_SIGNER_ROLE as _VALTZ_SIGNER_ROLE} from "./ValtzConstants.sol";
import "./lib/DemoMode.sol";

contract Valtz is AccessControl, DemoMode {
    address public immutable poolImplementation;
    bytes32 public constant VALTZ_SIGNER_ROLE = _VALTZ_SIGNER_ROLE;
    bytes32 public constant POOL_CREATOR_ADMIN_ROLE = keccak256("POOL_CREATOR_ADMIN_ROLE");

    // Registry of pools by subnetId
    mapping(bytes32 => address[]) public poolsBySubnet;

    /**
     * @dev Emitted when a new pool is created
     * @param pool The address of the new pool (indexed)
     * @param subnetId The subnet ID from the pool config (indexed)
     * @param creator The address that created the pool (indexed)
     */
    event CreatePool(address indexed pool, bytes32 indexed subnetId, address indexed creator);

    /**
     * @dev Constructor for Valtz contract.
     * @param defaultAdmin The address of the default admin.
     * @param _poolImplementation The address of the pool implementation contract.
     */
    constructor(address defaultAdmin, address _poolImplementation, bool _demoMode) {
        _setDemoMode(_demoMode);
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
        IValtzPool(pool).initialize(config, demoMode);

        // Add pool to registry
        poolsBySubnet[config.subnetID].push(pool);

        emit CreatePool(pool, config.subnetID, msg.sender);
    }

    /**
     * @notice Sets the demo mode state
     * @dev This function can only be called by the DEFAULT_ADMIN_ROLE
     * @param _demoMode The demo mode state to set
     */
    function setDemoMode(bool _demoMode) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDemoMode(_demoMode);
    }
}
