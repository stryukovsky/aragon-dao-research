// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

/// @notice This contract offloads the static deployment of the PluginSetupProcessor
contract PSPHelper {
    function deployStatic(
        address pluginRepoRegistry
    ) external returns (PluginSetupProcessor) {
        return new PluginSetupProcessor(PluginRepoRegistry(pluginRepoRegistry));
    }
}
