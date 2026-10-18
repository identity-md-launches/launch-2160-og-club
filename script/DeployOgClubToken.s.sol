// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {OgClubToken} from "../src/OgClubToken.sol";

/// @title Deploy script for Og Club (OG)
/// @notice For local and fork rehearsals only. The production launch is performed by the IMD
///         ProjectFactory from the attested bytecode; nobody runs this script against mainnet.
/// @dev `deploy()` takes no configuration because the token has no constructor arguments: it is
///      a pure function of the bytecode, and whoever sends the creation transaction receives the
///      supply. Tests call `deploy()` directly; `run()` only wraps it in a broadcast.
contract DeployOgClubToken is Script {
    /// @notice Deploys the token. The caller of the creation transaction receives the full supply.
    function deploy() public returns (OgClubToken token) {
        token = new OgClubToken();
    }

    /// @notice Broadcast entry point for `forge script`. Reads nothing from the environment.
    function run() external returns (OgClubToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
