// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {Executor as GlobalExecutor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {MultisigSetup} from "@aragon/multisig-plugin/MultisigSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting-plugin/TokenVotingSetup.sol";
import {GovernanceERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceWrappedERC20.sol";
import {StagedProposalProcessorSetup} from "@aragon/staged-proposal-processor-plugin/StagedProposalProcessorSetup.sol";

import {ProtocolFactory} from "../src/ProtocolFactory.sol";
import {FactoriesHelper} from "../src/FactoriesHelper.sol";
import {PSPHelper} from "../src/PSPHelper.sol";

/// @notice This local script triggers a full deploy of OSx, along with the core Aragon plugins and the Management DAO
/// @dev No privileged actions are performed within this file. All of them take place within the ProtocolFactory contract, on-chain.
/// @dev Given that deploying the factory with all contracts embedded would hit the gas limit, the deployment has two stages:
/// @dev 1) Deploy the raw contracts and store their addresses locally (this file)
/// @dev 2) Deploy the factory with the addresses above and tell it to orchestrate the protocol deployment
contract DeployScript is Script {
    string constant VERSION = "1.4";
    string constant DEFAULT_DAO_ENS_DOMAIN = "dao";
    string constant DEFAULT_PLUGIN_ENS_SUBDOMAIN = "plugin";
    string constant MANAGEMENT_DAO_MEMBERS_FILE_NAME = "multisig-members.json";

    DAO daoBase;
    DAORegistry daoRegistryBase;
    PluginRepoRegistry pluginRepoRegistryBase;
    PlaceholderSetup placeholderSetup;
    ENSSubdomainRegistrar ensSubdomainRegistrar;
    GlobalExecutor globalExecutor;

    AdminSetup adminSetup;
    MultisigSetup multisigSetup;
    TokenVotingSetup tokenVotingSetup;
    StagedProposalProcessorSetup stagedProposalProcessorSetup;

    ProtocolFactory factory;
    FactoriesHelper factoriesHelper;
    PSPHelper pspHelper;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deployment wallet:", vm.addr(privKey));
        console.log("Chain ID:", block.chainid);
        console.log();

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        deployOSxImplementations();
        deployCoreHelpers();

        deployAdminSetup();
        deployMultisigSetup();
        deployTokenVotingSetup();
        deployStagedProposalProcessorSetup();

        // Deploy the factory with immutable settings
        factory = new ProtocolFactory(getFactoryParams());
        vm.label(address(factory), "Factory");

        // Trigger the deployment
        factory.deployOnce();

        // Done
        printDeployment();
    }

    // Internal helpers

    function deployOSxImplementations() internal {
        /// @dev Deploy implementations with empty values. They will be used to create proxies and to verify the source code.
        daoBase = new DAO();
        vm.label(address(daoBase), "DAO Base");

        daoRegistryBase = new DAORegistry();
        vm.label(address(daoRegistryBase), "DAORegistry Base");

        // pluginRepo = new PluginRepo();

        pluginRepoRegistryBase = new PluginRepoRegistry();
        vm.label(address(pluginRepoRegistryBase), "PluginRepoRegistry Base");

        placeholderSetup = new PlaceholderSetup();
        vm.label(address(placeholderSetup), "PlaceholderSetup");

        ensSubdomainRegistrar = new ENSSubdomainRegistrar();
        vm.label(address(ensSubdomainRegistrar), "ENSSubdomainRegistrar Base");

        globalExecutor = new GlobalExecutor();
        vm.label(address(globalExecutor), "GlobalExecutor");

        /// @dev The DAOFactory, PluginRepoFactory and PluginSetupProcessor are static.
        /// @dev These contracts will be deployed by the FactoriesHelper and the PSPHelper.
    }

    function deployCoreHelpers() internal {
        factoriesHelper = new FactoriesHelper();
        vm.label(address(factoriesHelper), "FactoriesHelper");

        pspHelper = new PSPHelper();
        vm.label(address(pspHelper), "PSPHelper");
    }

    function deployAdminSetup() internal {
        adminSetup = new AdminSetup();
        vm.label(address(adminSetup), "AdminSetup");
    }

    function deployMultisigSetup() internal {
        multisigSetup = new MultisigSetup();
        vm.label(address(multisigSetup), "MultisigSetup");
    }

    function deployTokenVotingSetup() internal {
        tokenVotingSetup = new TokenVotingSetup(
            new GovernanceERC20(
                IDAO(address(0)),
                "",
                "",
                GovernanceERC20.MintSettings(new address[](0), new uint256[](0))
            ),
            new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "", "")
        );
        vm.label(address(tokenVotingSetup), "TokenVotingSetup");
    }

    function deployStagedProposalProcessorSetup() internal {
        stagedProposalProcessorSetup = new StagedProposalProcessorSetup();
        vm.label(
            address(stagedProposalProcessorSetup),
            "StagedProposalProcessorSetup"
        );
    }

    function readManagementDaoMembers()
        public
        view
        returns (address[] memory result)
    {
        // JSON list of members
        string memory path = string.concat(
            vm.projectRoot(),
            "/",
            MANAGEMENT_DAO_MEMBERS_FILE_NAME
        );
        string memory strJson = vm.readFile(path);

        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) {
            revert(
                "The file pointed by MANAGEMENT_DAO_MEMBERS_FILE_NAME does not exist"
            );
        }

        result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) {
            revert(
                "The file pointed by MANAGEMENT_DAO_MEMBERS_FILE_NAME needs to contain at least one member"
            );
        }
    }

    function readMetadataUris()
        internal
        view
        returns (ProtocolFactory.MetadataUris memory result)
    {
        result = ProtocolFactory.MetadataUris({
            managementDaoMetadata: vm.envOr(
                "MANAGEMENT_DAO_METADATA_URI",
                string("")
            ),
            adminPluginReleaseMetadata: vm.envOr(
                "ADMIN_PLUGIN_METADATA_URI",
                string("")
            ),
            adminPluginBuildMetadata: vm.envOr(
                "ADMIN_PLUGIN_BUILD_METADATA_URI",
                string("")
            ),
            multisigPluginReleaseMetadata: vm.envOr(
                "MULTISIG_PLUGIN_RELEASE_METADATA_URI",
                string("")
            ),
            multisigPluginBuildMetadata: vm.envOr(
                "MULTISIG_PLUGIN_BUILD_METADATA_URI",
                string("")
            ),
            tokenVotingPluginReleaseMetadata: vm.envOr(
                "TOKEN_VOTING_PLUGIN_RELEASE_METADATA_URI",
                string("")
            ),
            tokenVotingPluginBuildMetadata: vm.envOr(
                "TOKEN_VOTING_PLUGIN_BUILD_METADATA_URI",
                string("")
            ),
            stagedProposalProcessorPluginReleaseMetadata: vm.envOr(
                "STAGED_PROPOSAL_PROCESSOR_PLUGIN_RELEASE_METADATA_URI",
                string("")
            ),
            stagedProposalProcessorPluginBuildMetadata: vm.envOr(
                "STAGED_PROPOSAL_PROCESSOR_PLUGIN_BUILD_METADATA_URI",
                string("")
            )
        });
    }

    function getFactoryParams()
        internal
        view
        returns (ProtocolFactory.DeploymentParameters memory params)
    {
        params = ProtocolFactory.DeploymentParameters({
            osxImplementations: ProtocolFactory.OSxImplementations({
                daoBase: daoBase,
                daoRegistryBase: daoRegistryBase,
                // pluginRepo: pluginRepo,
                pluginRepoRegistryBase: pluginRepoRegistryBase,
                placeholderSetup: placeholderSetup,
                ensSubdomainRegistrar: ensSubdomainRegistrar,
                globalExecutor: globalExecutor
            }),
            factoriesHelper: factoriesHelper,
            pspHelper: pspHelper,
            ensParameters: ProtocolFactory.EnsParameters({
                daoRootDomain: vm.envOr(
                    "DAO_ENS_DOMAIN",
                    DEFAULT_DAO_ENS_DOMAIN
                ),
                pluginSubdomain: vm.envOr(
                    "PLUGIN_ENS_SUBDOMAIN",
                    DEFAULT_PLUGIN_ENS_SUBDOMAIN
                )
            }),
            pluginSetups: ProtocolFactory.PluginSetups({
                adminSetup: adminSetup,
                multisigSetup: multisigSetup,
                tokenVotingSetup: tokenVotingSetup,
                stagedProposalProcessorSetup: stagedProposalProcessorSetup
            }),
            metadataUris: readMetadataUris(),
            managementDaoMembers: readManagementDaoMembers()
        });
    }

    function printDeployment() internal view {
        console.log("Deploying OSX version", VERSION);

        ProtocolFactory.Deployment memory deployment = factory.getDeployment();

        console.log();
        console.log("Static contracts:");
        console.log("- DAOFactory", deployment.daoFactory);
        console.log("- PluginRepoFactory", deployment.pluginRepoFactory);
        console.log("- PluginSetupProcessor", deployment.pluginSetupProcessor);

        console.log();
        console.log("Proxy contracts:");

        console.log();
        console.log("Protocol helpers:");
        console.log("- Management DAO", deployment.managementDao);
        console.log(
            "- Management DAO multisig",
            deployment.managementDaoMultisig
        );

        console.log();
        console.log("Implementations:");
        // console.log("- DAO", deployment.dao);
        console.log("- DAORegistry", deployment.daoRegistry);
        // console.log("- PluginRepo", deployment.pluginRepo);
        console.log("- PluginRepoRegistry", deployment.pluginRepoRegistry);
        console.log("- PlaceholderSetup", deployment.placeholderSetup);
        console.log(
            "- DAO ENSSubdomainRegistrar",
            deployment.daoSubdomainRegistrar
        );
        console.log(
            "- Plugin ENSSubdomainRegistrar",
            deployment.pluginSubdomainRegistrar
        );
        console.log("- GlobalExecutor", deployment.globalExecutor);

        console.log();
        console.log("Plugin repositories:");
    }
}
