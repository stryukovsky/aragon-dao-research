// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {PluginSetupProcessor, PluginSetupRef, hashHelpers} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {Executor as GlobalExecutor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

import {ENSRegistry} from "@ensdomains/ens-contracts/contracts/registry/ENSRegistry.sol";
import {PublicResolver, INameWrapper} from "@ensdomains/ens-contracts/contracts/resolvers/PublicResolver.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";

import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {Multisig} from "@aragon/multisig-plugin/Multisig.sol";
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
    bytes32 private constant ROOT_NODE = 0x0;
    bytes32 private constant ETH_LABEL = keccak256("eth");
    string constant MANAGEMENT_DAO_SUBDOMAIN = "management";
    bytes constant MANAGEMENT_DAO_METADATA_URI =
        "ipfs://bafkreibemfrxeuwfaono6k37vbi66fctcwtioiyctrl4fvqtqmiodt2mle";
    uint8 constant MANAGEMENT_DAO_MIN_APPROVALS = 3;
    uint8 constant MULTISIG_PLUGIN_RELEASE = 1;
    uint8 constant MULTISIG_PLUGIN_BUILD = 3;

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
        DAORegistry daoRegistryBase;
        PluginRepoRegistry pluginRepoRegistryBase;
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
        address daoSubdomainRegistrar;
        address pluginSubdomainRegistrar;
        address publicResolver;
        // Plugin Repo's
        address adminPluginRepo;
        address multisigPluginRepo;
        address tokenVotingPluginRepo;
        address stagedProposalProcessorPluginRepo;
    }

    /// @notice Emitted when deployOnce() has been called and the deployment is complete.
    /// @param factory The address of the factory contract where the parameters and addresses can be retrieved.
    event ProtocolDeployed(ProtocolFactory factory);

    /// @notice Thrown when attempting to call deployOnce() when the protocol is already deployed.
    error AlreadyDeployed();

    DeploymentParameters private parameters;
    Deployment private deployment;

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

        // Prepare the plugin repo's and their versions
        // prepareAdminPlugin();
        // prepareMultisigPlugin();
        // prepareTokenVotingPlugin();
        // prepareSppPlugin();

        // Drop the factory's permissions on the management DAO
        concludeManagementDao();
        removePermissions();

        emit ProtocolDeployed(this);
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

        bytes32 ETH_NODE;
        bytes32 DAO_NODE;
        bytes32 PLUGIN_DAO_NODE;
        bytes32 DAO_LABEL = keccak256(
            bytes(parameters.ensParameters.daoRootDomain)
        );
        bytes32 PLUGIN_DAO_LABEL = keccak256(
            bytes(parameters.ensParameters.pluginSubdomain)
        );

        // ENS Registry and PublicResolver
        ENSRegistry ensRegistry = new ENSRegistry();
        deployment.ensRegistry = address(ensRegistry);

        deployment.publicResolver = address(
            new PublicResolver(ensRegistry, INameWrapper(address(0)))
        );

        // The deployer of ENSRegistry becomes the owner of the root node (0x0).

        // Hold temporary ownership to set the resolver

        ETH_NODE = ensRegistry.setSubnodeOwner(
            ROOT_NODE,
            ETH_LABEL,
            address(this) // deployment.managementDao
        );

        DAO_NODE = ensRegistry.setSubnodeOwner(
            ETH_NODE,
            DAO_LABEL,
            address(this) // deployment.managementDao
        );
        ensRegistry.setResolver(DAO_NODE, deployment.publicResolver);

        PLUGIN_DAO_NODE = ensRegistry.setSubnodeOwner(
            DAO_NODE,
            PLUGIN_DAO_LABEL,
            address(this) // deployment.managementDao
        );
        ensRegistry.setResolver(PLUGIN_DAO_NODE, deployment.publicResolver);

        // Set the Management DAO as the final owner (reverse order)
        ensRegistry.setSubnodeOwner(
            DAO_NODE,
            PLUGIN_DAO_LABEL,
            deployment.managementDao
        );
        ensRegistry.setSubnodeOwner(
            ETH_NODE,
            DAO_LABEL,
            deployment.managementDao
        );
        ensRegistry.setSubnodeOwner(
            ROOT_NODE,
            ETH_LABEL,
            deployment.managementDao
        );

        // Deploy the dao.eth ENSSubdomainRegistrar
        deployment.daoSubdomainRegistrar = createProxyAndCall(
            address(parameters.osxImplementations.ensSubdomainRegistrar),
            abi.encodeCall(
                ENSSubdomainRegistrar.initialize,
                (
                    IDAO(deployment.managementDao),
                    ENSRegistry(deployment.ensRegistry),
                    DAO_NODE
                )
            )
        );

        // Deploy the plugin.dao.eth ENSSubdomainRegistrar
        deployment.pluginSubdomainRegistrar = createProxyAndCall(
            address(parameters.osxImplementations.ensSubdomainRegistrar),
            abi.encodeCall(
                ENSSubdomainRegistrar.initialize,
                (
                    IDAO(deployment.managementDao),
                    ENSRegistry(deployment.ensRegistry),
                    PLUGIN_DAO_NODE
                )
            )
        );

        // Allow the registrars to register subdomains
        ensRegistry.setApprovalForAll(deployment.daoSubdomainRegistrar, true);
        ensRegistry.setApprovalForAll(
            deployment.pluginSubdomainRegistrar,
            true
        );
    }

    function prepareOSx() internal {
        // Deploy the DAORegistry proxy
        deployment.daoRegistry = createProxyAndCall(
            address(parameters.osxImplementations.daoRegistryBase),
            abi.encodeCall(
                DAORegistry.initialize,
                (
                    IDAO(deployment.managementDao),
                    ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar)
                )
            )
        );

        // Deploy PluginRepoRegistry proxy
        deployment.pluginRepoRegistry = createProxyAndCall(
            address(parameters.osxImplementations.pluginRepoRegistryBase),
            abi.encodeCall(
                PluginRepoRegistry.initialize,
                (
                    IDAO(deployment.managementDao),
                    ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar)
                )
            )
        );

        // Static contract deployments
        deployment.pluginRepoFactory = address(
            new PluginRepoFactory(
                PluginRepoRegistry(deployment.pluginRepoRegistry)
            )
        );
        deployment.pluginSetupProcessor = address(
            new PluginSetupProcessor(
                PluginRepoRegistry(deployment.pluginRepoRegistry)
            )
        );
        deployment.daoFactory = address(
            new DAOFactory(
                DAORegistry(deployment.daoRegistry),
                PluginSetupProcessor(deployment.pluginSetupProcessor)
            )
        );

        // Storing implementation addresses
        deployment.globalExecutor = address(
            parameters.osxImplementations.globalExecutor
        );
        deployment.placeholderSetup = address(
            parameters.osxImplementations.placeholderSetup
        );
    }

    function preparePermissions() internal {
        DAO managementDao = DAO(payable(deployment.managementDao));

        // ENS registrar permissions

        // Allow to register subdomains
        managementDao.grant(
            deployment.daoSubdomainRegistrar,
            deployment.daoRegistry,
            ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar)
                .REGISTER_ENS_SUBDOMAIN_PERMISSION_ID()
        );
        managementDao.grant(
            deployment.pluginSubdomainRegistrar,
            deployment.pluginRepoRegistry,
            ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar)
                .REGISTER_ENS_SUBDOMAIN_PERMISSION_ID()
        );

        // Allow to perform upgrades
        managementDao.grant(
            deployment.daoSubdomainRegistrar,
            deployment.managementDao,
            ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar)
                .UPGRADE_REGISTRAR_PERMISSION_ID()
        );
        managementDao.grant(
            deployment.pluginSubdomainRegistrar,
            deployment.managementDao,
            ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar)
                .UPGRADE_REGISTRAR_PERMISSION_ID()
        );

        // DAORegistry permissions

        // Register DAO's
        managementDao.grant(
            deployment.daoRegistry,
            deployment.daoFactory,
            DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID()
        );
        // Upgrade the implementation
        managementDao.grant(
            deployment.daoRegistry,
            deployment.managementDao,
            DAORegistry(deployment.daoRegistry).UPGRADE_REGISTRY_PERMISSION_ID()
        );

        // PluginRepoRegistry permissions

        // Register plugins
        managementDao.grant(
            deployment.pluginRepoRegistry,
            deployment.pluginRepoFactory,
            PluginRepoRegistry(deployment.pluginRepoRegistry)
                .REGISTER_PLUGIN_REPO_PERMISSION_ID()
        );
        // Upgrade the implementation
        managementDao.grant(
            deployment.pluginRepoRegistry,
            deployment.managementDao,
            PluginRepoRegistry(deployment.pluginRepoRegistry)
                .UPGRADE_REGISTRY_PERMISSION_ID()
        );
    }

    function prepareAdminPlugin() internal {}

    function prepareMultisigPlugin() internal {}

    function prepareTokenVotingPlugin() internal {}

    function prepareSppPlugin() internal {}

    function concludeManagementDao() internal {
        DAO managementDao = DAO(payable(deployment.managementDao));

        // Grant temporary permissions for the factory to register the Management DAO
        managementDao.grant(
            deployment.daoRegistry,
            address(this),
            DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID()
        );

        // Register the ManagementDAO on the DaoRegistry
        DAORegistry(deployment.daoRegistry).register(
            managementDao,
            address(this),
            MANAGEMENT_DAO_SUBDOMAIN
        );

        // Revoke the temporary permission
        managementDao.revoke(
            deployment.daoRegistry,
            address(this),
            DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID()
        );

        // Set the Management DAO metadata

        // Grant temporary permissions for the factory to register the Management DAO
        managementDao.grant(
            deployment.managementDao,
            address(this),
            managementDao.SET_METADATA_PERMISSION_ID()
        );

        managementDao.setMetadata(MANAGEMENT_DAO_METADATA_URI);

        // Revoke the temporary permission
        managementDao.revoke(
            deployment.managementDao,
            address(this),
            managementDao.SET_METADATA_PERMISSION_ID()
        );

        // Management DAO Multisig Plugin

        // Prepare the installation
        bytes memory setupData = abi.encode(
            parameters.managementDaoMembers,
            Multisig.MultisigSettings({
                onlyListed: true,
                minApprovals: MANAGEMENT_DAO_MIN_APPROVALS
            }),
            IPlugin.TargetConfig({
                target: deployment.managementDao,
                operation: IPlugin.Operation.Call
            }),
            bytes("") // metadata
        );

        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(MULTISIG_PLUGIN_RELEASE, MULTISIG_PLUGIN_BUILD),
            PluginRepo(deployment.multisigPluginRepo)
        );
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (
            deployment.managementDaoMultisig,
            preparedSetupData
        ) = PluginSetupProcessor(deployment.pluginSetupProcessor)
            .prepareInstallation(
                deployment.managementDao,
                PluginSetupProcessor.PrepareInstallationParams(
                    pluginSetupRef,
                    setupData
                )
            );

        // Grant temporary permissions to apply the installation
        managementDao.grant(
            address(managementDao),
            deployment.pluginSetupProcessor,
            managementDao.ROOT_PERMISSION_ID()
        );
        managementDao.grant(
            deployment.pluginSetupProcessor,
            address(this),
            PluginSetupProcessor(deployment.pluginSetupProcessor)
                .APPLY_INSTALLATION_PERMISSION_ID()
        );

        // Install the plugin
        PluginSetupProcessor(deployment.pluginSetupProcessor).applyInstallation(
                address(managementDao),
                PluginSetupProcessor.ApplyInstallationParams(
                    pluginSetupRef,
                    deployment.managementDaoMultisig,
                    preparedSetupData.permissions,
                    hashHelpers(preparedSetupData.helpers)
                )
            );

        // Remove the temporary permissions
        managementDao.revoke(
            address(managementDao),
            deployment.pluginSetupProcessor,
            managementDao.ROOT_PERMISSION_ID()
        );
        managementDao.revoke(
            deployment.pluginSetupProcessor,
            address(this),
            PluginSetupProcessor(deployment.pluginSetupProcessor)
                .APPLY_INSTALLATION_PERMISSION_ID()
        );
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
