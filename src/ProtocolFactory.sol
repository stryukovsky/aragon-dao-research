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
import {Executor as GlobalExecutor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

import {ENSRegistry} from "@ensdomains/ens-contracts/contracts/registry/ENSRegistry.sol";
import {PublicResolver} from "@ensdomains/ens-contracts/contracts/resolvers/PublicResolver.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";

import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {MultisigSetup} from "@aragon/multisig-plugin/MultisigSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting-plugin/TokenVotingSetup.sol";
import {StagedProposalProcessorSetup} from "@aragon/staged-proposal-processor-plugin/StagedProposalProcessorSetup.sol";

import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice This contract orchestrates the full protocol deployment, including the Managing DAO, OSx and Aragon's core plugins.
/// @dev Given that deploying the factory with all contracts embedded would hit the gas limit, the deployment has two stages:
/// @dev 1) Deploy the raw contracts and store their addresses locally
/// @dev 2) Deploy the factory with the addresses above and tell it to orchestrate the protocol deployment (this file)
contract ProtocolFactory {
    /// @notice The struct containing all the parameters to deploy the protocol
    struct DeploymentParameters {
        OSxImplementations osxImplementations;
        EnsParameters ensParameters;
        PluginSetups pluginSetups;
        MetadataUris metadataUris;
        address[] managementDaoMembers;
    }

    /// @notice The struct containing the implementation addresses for OSx
    struct OSxImplementations {
        DAO daoBase;
        // DAORegistry daoRegistry;
        // PluginRepo pluginRepo;
        PluginRepoRegistry pluginRepoRegistry;
        PlaceholderSetup placeholderSetup;
        ENSSubdomainRegistrar ensSubdomainRegistrar;
        GlobalExecutor globalExecutor;
    }

    /// @notice The struct containing the ENS related parameters
    struct EnsParameters {
        /// @notice The root domain to use for DAO's on the DaoRegistry (example: "dao" => dao.eth)
        string daoRootDomain;
        /// @notice The subdomain name to use for the PluginRepoRegistry (example: "plugin" => plugin.dao.eth)
        string pluginSubdomain;
    }

    /// @notice The struct containing the deployed plugin setup's for the Aragon core plugins
    struct PluginSetups {
        AdminSetup adminSetup;
        MultisigSetup multisigSetup;
        TokenVotingSetup tokenVotingSetup;
        StagedProposalProcessorSetup stagedProposalProcessorSetup;
    }

    /// @notice The struct containing the URI's of the protocol contracts as well as the core plugin repo's
    struct MetadataUris {
        string managementDaoMetadata;
        string adminPluginReleaseMetadata;
        string adminPluginBuildMetadata;
        string multisigPluginReleaseMetadata;
        string multisigPluginBuildMetadata;
        string tokenVotingPluginReleaseMetadata;
        string tokenVotingPluginBuildMetadata;
        string stagedProposalProcessorPluginReleaseMetadata;
        string stagedProposalProcessorPluginBuildMetadata;
    }

    /// @notice The struct containing the deployed protocol addresses
    struct Deployment {
        // OSx static contracts
        address daoFactory;
        address pluginRepoFactory;
        address pluginSetupProcessor;
        address globalExecutor;
        address placeholderSetup;
        // OSx proxies
        // address dao;
        // address pluginRepo;
        address daoRegistry;
        address pluginRepoRegistry;
        address managementDao;
        address managementDaoMultisig;
        // ENS
        address ensRegistry;
        address ensSubdomainRegistrar;
        address publicResolver;
        // Plugin Repo's
    }

    /// @notice Emitted when deployOnce() has been called and the deployment is complete.
    /// @param factory The address of the factory contract where the parameters and addresses can be retrieved.
    event ProtocolDeployed(ProtocolFactory factory);

    /// @notice Thrown when attempting to call deployOnce() when the protocol is already deployed.
    error AlreadyDeployed();

    DeploymentParameters parameters;
    Deployment deployment;

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _parameters The parameters of the one-time deployment.
    constructor(DeploymentParameters memory _parameters) {
        parameters = _parameters;
    }

    function deployOnce() external {
        if (address(deployment.daoFactory) != address(0)) {
            revert AlreadyDeployed();
        }

        // Create the DAO that will own the registries and the core plugin repo's
        prepareManagementDao();

        // Set up the ENS registry and the requested domains
        prepareEnsRegistry();

        // Deploy the OSx core contracts
        prepareOSx();

        preparePermissions();

        // // Prepare the plugin repo's and their versions
        // prepareAdminPlugin();
        // prepareMultisigPlugin();
        // prepareTokenVotingPlugin();
        // prepareSppPlugin();

        // // Drop the factory's permissions on the management DAO
        // concludeManagementDao();
        // removePermissions();

        // emit ProtocolDeployed(this);
    }

    /// @notice Returns the parameters used by the factory to deploy the protocol
    function getParameters()
        external
        view
        returns (DeploymentParameters memory)
    {
        return parameters;
    }

    /// @notice Returns the addresses of the OSx contracts as well as the the core plugins
    function getDeployment() external view returns (Deployment memory) {
        return deployment;
    }

    // Internal helpers

    function prepareManagementDao() internal {
        DAO managementDao = DAO(
            payable(
                createProxyAndCall(
                    address(parameters.osxImplementations.daoBase),
                    abi.encodeCall(
                        DAO.initialize,
                        (
                            bytes(
                                parameters.metadataUris.managementDaoMetadata
                            ), // Metadata URI
                            address(this), // initialOwner
                            address(0), // Trusted forwarder
                            "" // DAO URI
                        )
                    )
                )
            )
        );
        deployment.managementDao = address(managementDao);

        // Grant the DAO the required permissions on itself

        // Available:
        // - ROOT_PERMISSION
        // - UPGRADE_DAO_PERMISSION
        // - REGISTER_STANDARD_CALLBACK_PERMISSION
        // - SET_SIGNATURE_VALIDATOR_PERMISSION      [skipped]
        // - SET_TRUSTED_FORWARDER_PERMISSION        [skipped]
        // - SET_METADATA_PERMISSION                 [skipped]

        PermissionLib.SingleTargetPermission[]
            memory items = new PermissionLib.SingleTargetPermission[](3);
        items[0] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            deployment.managementDao,
            managementDao.ROOT_PERMISSION_ID()
        );
        items[1] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            deployment.managementDao,
            managementDao.UPGRADE_DAO_PERMISSION_ID()
        );
        items[2] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            deployment.managementDao,
            managementDao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID()
        );

        managementDao.applySingleTargetPermissions(
            deployment.managementDao,
            items
        );

        // Grant the factory execute permission on the Management DAO
        managementDao.grant(
            deployment.managementDao,
            address(this),
            managementDao.EXECUTE_PERMISSION_ID()
        );
    }

    function prepareEnsRegistry() internal {
        // Set up an ENS environment

        deployment.ensRegistry = new ENSRegistry();
        // deployment.ensSubdomainRegistrar = new ENSSubdomainRegistrar();
        deployment.publicResolver = new PublicResolver(
            ENSRegistry(deployment.ensRegistry),
            address(0)
        );

        // Deploy an ENSSubdomainRegistrar
        // Register the DAO domain
        // Register the Plugin domain
    }

    function prepareOSx() internal {
        // TODO:
        // Deploy DAORegistry proxy
        // Deploy PluginRepoRegistry proxy

        deployment.pluginSetupProcessor = address(
            new PluginSetupProcessor(PluginRepoRegistry(address(0)))
        );
        // deployment.pluginRepoFactory = address(
        //     new PluginRepoFactory(PluginRepoRegistry(address(0)))
        // );
        // deployment.daoFactory = address(
        //     new DAOFactory(
        //         DAORegistry(address(0)),
        //         PluginSetupProcessor(deployment.pluginSetupProcessor)
        //     )
        // );

        deployment.globalExecutor = address(
            parameters.osxImplementations.globalExecutor
        );
        deployment.placeholderSetup = address(
            parameters.osxImplementations.placeholderSetup
        );
    }

    function preparePermissions() internal {
        // ENS permissions
        // DAOREgistry permissions
        // PluginRepoRegistry permissions
    }

    function prepareAdminPlugin() internal {}

    function prepareMultisigPlugin() internal {}

    function prepareTokenVotingPlugin() internal {}

    function prepareSppPlugin() internal {}

    function concludeManagementDao() internal {
        // Register the ManagementDAO on the DaoRegistry
        // Temporarily grant permissions to the factory to do so
        //
        // Install the multisig plugin
    }

    function removePermissions() internal {
        // Remove the execute permission from the factory
        DAO(payable(deployment.managementDao)).revoke(
            deployment.managementDao, // where
            address(this), // who
            DAO(payable(deployment.managementDao)).EXECUTE_PERMISSION_ID() // permission
        );
    }

    function createProxyAndCall(
        address _logic,
        bytes memory _data
    ) internal returns (address) {
        return address(new ERC1967Proxy(_logic, _data));
    }
}
