// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";

/// @notice This contract offloads the deployment of the PluginRepoFactory
contract PluginRepoHelper {
    function deployFactory(
        address pluginRepoRegistry
    ) external returns (PluginRepoFactory pluginRepoFactory) {
        pluginRepoFactory = new PluginRepoFactory(
            PluginRepoRegistry(pluginRepoRegistry)
        );
    }
}
