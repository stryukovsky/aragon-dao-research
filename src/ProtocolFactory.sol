// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
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

import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {MultisigSetup} from "@aragon/multisig-plugin/MultisigSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting-plugin/TokenVotingSetup.sol";
import {StagedProposalProcessorSetup} from "@aragon/staged-proposal-processor-plugin/StagedProposalProcessorSetup.sol";

/// @notice This contract orchestrates the full protocol deployment, including the Managing DAO, OSx and Aragon's core plugins.
/// @dev Given that deploying the factory with all contracts embedded would hit the gas limit, the deployment has two stages:
/// @dev 1) Deploy the raw contracts and store their addresses locally
/// @dev 2) Deploy the factory with the addresses above and tell it to orchestrate the protocol deployment (this file)
contract ProtocolFactory {
    /// @notice The struct containing all the parameters to deploy the protocol
    struct DeploymentParameters {
        OSxImplementations osxImplementations;
        PluginSetups pluginSetups;
        address[] managementDaoMembers;
    }

    /// @notice The struct containing the implementation addresses for OSx
    struct OSxImplementations {
        DAO dao;
        DAORegistry daoRegistry;
        PluginRepo pluginRepo;
        PluginRepoRegistry pluginRepoRegistry;
        PlaceholderSetup placeholderSetup;
        ENSSubdomainRegistrar ensSubdomainRegistrar;
        GlobalExecutor globalExecutor;
    }

    /// @notice The struct containing the deployed plugin setup's for the Aragon core plugins
    struct PluginSetups {
        AdminSetup adminSetup;
        MultisigSetup multisigSetup;
        TokenVotingSetup tokenVotingSetup;
        StagedProposalProcessorSetup stagedProposalProcessorSetup;
    }

    /// @notice The struct containing the deployed protocol addresses
    struct Deployment {
        // OSx implementations
        DAO dao;
        DAORegistry daoRegistry;
        PluginRepo pluginRepo;
        PluginRepoRegistry pluginRepoRegistry;
        PlaceholderSetup placeholderSetup;
        ENSSubdomainRegistrar ensSubdomainRegistrar;
        GlobalExecutor globalExecutor;
        // OSx static contracts
        DAOFactory daoFactory;
        PluginRepoFactory pluginRepoFactory;
        PluginSetupProcessor pluginSetupProcessor;
        // Plugin Repo's
    }

    /// @notice Thrown when attempting to call deployOnce() when the protocol is already deployed.
    error AlreadyDeployed();

    DeploymentParameters public parameters;
    Deployment public deployment;

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _parameters The parameters of the one-time deployment.
    constructor(DeploymentParameters memory _parameters) {
        parameters = _parameters;
    }

    function deployOnce() external {
        if (address(deployment.dao) != address(0)) revert AlreadyDeployed();

        // TODO
    }

    // Internal helpers

    function prepareManagementDao() internal {}

    function prepareOSx() internal {
        deployment.daoFactory = new DAOFactory(
            DAORegistry(address(0)),
            PluginSetupProcessor(address(0))
        );
        deployment.pluginRepoFactory = new PluginRepoFactory(
            PluginRepoRegistry(address(0))
        );
        deployment.pluginSetupProcessor = new PluginSetupProcessor(
            PluginRepoRegistry(address(0))
        );
    }
}
