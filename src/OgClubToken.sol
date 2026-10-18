// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Og Club (OG)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 OG (18 decimals) is minted once,
///         in the constructor, to the deployer (`msg.sender`). Nothing can mint afterwards.
/// @dev Deliberately minimal: no owner, no pause, no blocklist, no fee on transfer, no hooks.
///      Every transfer moves exactly the amount requested, so the launch flows (factory to
///      distributor, distributor to claimants, pool seeding and swaps) arrive whole.
///      The deployer at launch is the IMD ProjectFactory, which pays the supply out; this contract
///      neither knows nor needs its address.
contract OgClubToken is ERC20 {
    /// @notice Token name as returned by `name()`.
    string public constant TOKEN_NAME = "Og Club";

    /// @notice Token symbol as returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "OG";

    /// @notice Number of decimals, the ERC-20 default.
    uint8 public constant DECIMALS = 18;

    /// @notice The entire, fixed supply in minor units: 1,000,000,000 * 10**18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Mints `TOTAL_SUPPLY` to the deployer. Takes no arguments and calls no other contract.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
