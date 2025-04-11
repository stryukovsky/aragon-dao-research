// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {Executor as GlobalExecutor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

/// @notice Performs a full deploy of OSx, along with the core Aragon plugins and the Management DAO
/// @dev Given that deployong all the contracts within the factory would hit the gas limit, the script does the deployment in two stages:
/// @dev 1) Deploy the raw contracts and store their address locally
/// @dev 2) Deploy the factory with the addresses above and tell it to orchestrate the protocol deployment
contract DeployScript is Script {
    DAO dao;
    DAORegistry daoRegistry;
    PluginRepo pluginRepo;
    PluginRepoRegistry pluginRepoRegistry;
    PlaceholderSetup placeholderSetup;
    ENSSubdomainRegistrar ensSubdomainRegistrar;
    GlobalExecutor globalExecutor;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deployment wallet:", vm.addr(privKey));
        console.log("Chain ID:", block.chainid);
        console.log("");

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        deployOSxImplementations();
    }

    // Internal helpers

    function deployOSxImplementations() internal {
        /// @dev Deploy an implementation with empty values
        dao = new DAO();
        daoRegistry = new DAORegistry();
        pluginRepo = new PluginRepo();
        pluginRepoRegistry = new PluginRepoRegistry();
        placeholderSetup = new PlaceholderSetup();
        ensSubdomainRegistrar = new ENSSubdomainRegistrar();
        globalExecutor = new GlobalExecutor();
    }

    function deployAdminPluginContracts() internal {}

    function deployMultisigPluginContracts() internal {}

    function deployTokenVotingPluginContracts() internal {}

    function deployStagedProposalProcessorPluginContracts() internal {}

    function getFactoryParams() internal {}
}
