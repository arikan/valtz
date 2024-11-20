// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IValtzPool} from "./ValtzPool.sol";
import {VALTZ_SIGNER_ROLE as _VALTZ_SIGNER_ROLE} from "./ValtzConstants.sol";
import {DemoMode} from "./lib/DemoMode.sol";

contract Valtz is AccessControl, DemoMode {
    /// @notice The address of the implementation contract used for creating new pools
    /// @dev This is immutable and set during contract deployment
    address public immutable poolImplementation;

    /// @notice Role identifier for Valtz signers
    bytes32 public constant VALTZ_SIGNER_ROLE = _VALTZ_SIGNER_ROLE;

    /// @notice Role identifier for administrators who can create pools
    bytes32 public constant POOL_CREATOR_ADMIN_ROLE = keccak256("POOL_CREATOR_ADMIN_ROLE");

    /// @notice Array containing addresses of all created pools
    /// @dev Used to track and iterate over all pools in the system
    address[] public pools;

    /// @notice Mapping of subnet IDs to arrays of pool addresses
    /// @dev Allows lookup of all pools associated with a specific subnet
    /// @dev Key is the subnet ID, value is an array of pool addresses
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
        pools.push(pool);
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

    /**
     * @notice Returns the total number of pools created
     * @dev Gets the length of the pools array
     * @return uint256 The total count of all pools
     */
    function poolCount() external view returns (uint256) {
        return pools.length;
    }

    /**
     * @notice Returns an array of all pool addresses
     * @dev Returns the complete pools array
     * @return address[] An array containing the addresses of all created pools
     */
    function allPools() external view returns (address[] memory) {
        return pools;
    }
}
