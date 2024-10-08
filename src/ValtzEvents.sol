// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Emitted when a new pool is created
 * @param pool The address of the new pool
 */
event CreatePool(address pool);

/**
 * @dev Emitted when a Valtz pool starts.
 * @param startTime The timestamp when the Valtz pool starts.
 */
event ValtzPoolStart(uint40 startTime);

/**
 * @dev Emitted when a deposit is made into the Valtz pool, with pool tokens minted.
 * @param depositor The address of the account making the deposit.
 * @param receiver The address of the account receiving the pool tokens.
 * @param amount The amount of tokens deposited.
 */
event ValtzPoolDeposit(address indexed depositor, address indexed receiver, uint256 amount);

/**
 * @dev Emitted when a user redeems tokens from the Valtz pool.
 * @param redeemer The address of the account redeeming tokens.
 * @param receiver The address of the account receiving tokens.
 * @param poolTokenAmount The amount of pool tokens redeemed.
 * @param tokenAmountWithdrawn The amount of tokens withdrawn.
 */
event ValtzPoolRedeem(
    address indexed redeemer,
    address indexed receiver,
    uint256 poolTokenAmount,
    uint256 tokenAmountWithdrawn
);
