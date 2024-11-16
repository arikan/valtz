// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {FUJI_CHAIN_ID, HARDHAT_CHAIN_ID, GANACHE_CHAIN_ID} from "../ValtzConstants.sol";

abstract contract DemoMode {
    /// @notice Whether the contract is in demo mode, which relaxes validation checks
    bool public demoMode;

    error DemoModeNotAllowed();

    /**
     * @dev Internal function to set demo mode
     * @param _demoMode The demo mode state to set
     */
    function _setDemoMode(bool _demoMode) internal {
        if (block.chainid != FUJI_CHAIN_ID && block.chainid != HARDHAT_CHAIN_ID && block.chainid != GANACHE_CHAIN_ID) {
            revert DemoModeNotAllowed();
        }

        demoMode = _demoMode;
    }
}
