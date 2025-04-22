// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginSetupProcessor, PluginSetupRef, hashHelpers} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

/// @notice This contract offloads the deployment of the OSx static factories
contract FactoriesHelper {
    struct Parameters {
        address daoRegistry;
        address pluginRepoRegistry;
        address pluginSetupProcessor;
    }

    // Static contract deployments
    function deployStatic(
        Parameters memory params
    ) external returns (address daoFactory, address pluginRepoFactory) {
        daoFactory = address(
            new DAOFactory(
                DAORegistry(params.daoRegistry),
                PluginSetupProcessor(params.pluginSetupProcessor)
            )
        );
        pluginRepoFactory = address(
            new PluginRepoFactory(PluginRepoRegistry(params.pluginRepoRegistry))
        );
    }
}
