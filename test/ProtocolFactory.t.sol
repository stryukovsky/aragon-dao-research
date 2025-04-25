// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {AragonTest} from "./helpers/AragonTest.sol";
import {ProtocolFactoryBuilder} from "./helpers/ProtocolFactoryBuilder.sol";
import {ProtocolFactory} from "../src/ProtocolFactory.sol";

// OSx Imports
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor, PluginSetupRef, hashHelpers} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {Multisig} from "@aragon/multisig-plugin/Multisig.sol";

// ENS Imports
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {PublicResolver} from "@ensdomains/ens-contracts/contracts/resolvers/PublicResolver.sol";
import {ENSHelper} from "../src/helpers/ENSHelper.sol";

// Plugin Setups
import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {MultisigSetup} from "@aragon/multisig-plugin/MultisigSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting-plugin/TokenVotingSetup.sol";
import {StagedProposalProcessorSetup} from "@aragon/staged-proposal-processor-plugin/StagedProposalProcessorSetup.sol";
import {GovernanceERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceERC20.sol";

interface IResolver {
    function addr(bytes32 node) external view returns (address);
}

contract ProtocolFactoryTest is AragonTest {
    ProtocolFactoryBuilder builder;
    ProtocolFactory factory;
    ProtocolFactory.DeploymentParameters deploymentParams;
    ProtocolFactory.Deployment deployment;

    address[] internal mgmtDaoMembers;

    // Namehashes calculated in setUp for reuse
    bytes32 ethNode;
    bytes32 daoRootNode; // e.g., dao-test.eth
    bytes32 pluginRootNode; // e.g., plugin-test.dao-test.eth
    bytes32 managementDaoNode; // e.g., management-test.dao-test.eth

    function setUp() public {
        builder = new ProtocolFactoryBuilder();

        // Configure some basic params for testing
        mgmtDaoMembers = new address[](3);
        mgmtDaoMembers[0] = alice;
        mgmtDaoMembers[1] = bob;
        mgmtDaoMembers[2] = carol;

        builder
            .withManagementDaoMembers(mgmtDaoMembers)
            .withManagementDaoMinApprovals(2);

        // Build the factory (deploys factory contract but doesn't call deployOnce yet)
        factory = builder.build();

        deploymentParams = builder.getDeploymentParams();

        // Pre-calculate namehashes based on params
        ethNode = vm.ensNamehash("eth");
        daoRootNode = vm.ensNamehash(
            string.concat(deploymentParams.ensParameters.daoRootDomain, ".eth")
        );
        pluginRootNode = vm.ensNamehash(
            string.concat(
                deploymentParams.ensParameters.pluginSubdomain,
                ".",
                deploymentParams.ensParameters.daoRootDomain,
                ".eth"
            )
        );
        managementDaoNode = vm.ensNamehash(
            string.concat(
                deploymentParams.ensParameters.managementDaoSubdomain,
                ".",
                deploymentParams.ensParameters.daoRootDomain,
                ".eth"
            )
        );
    }

    function test_WhenDeployingTheProtocolFactory() external {
        // It getParameters should return the exact same parameters as provided to the constructor
        ProtocolFactory.DeploymentParameters memory currentParams = factory
            .getParameters();

        // Deep comparison
        assertEq(
            keccak256(abi.encode(currentParams)),
            keccak256(abi.encode(deploymentParams))
        );

        // It getDeployment should return empty values (zero addresses)
        deployment = factory.getDeployment();
        assertEq(deployment.daoFactory, address(0));
        assertEq(deployment.pluginRepoFactory, address(0));
        assertEq(deployment.pluginSetupProcessor, address(0));
        assertEq(deployment.globalExecutor, address(0));
        assertEq(deployment.placeholderSetup, address(0));
        assertEq(deployment.daoRegistry, address(0));
        assertEq(deployment.pluginRepoRegistry, address(0));
        assertEq(deployment.managementDao, address(0));
        assertEq(deployment.managementDaoMultisig, address(0));
        assertEq(deployment.ensRegistry, address(0));
        assertEq(deployment.daoSubdomainRegistrar, address(0));
        assertEq(deployment.pluginSubdomainRegistrar, address(0));
        assertEq(deployment.publicResolver, address(0));
        assertEq(deployment.adminPluginRepo, address(0));
        assertEq(deployment.multisigPluginRepo, address(0));
        assertEq(deployment.tokenVotingPluginRepo, address(0));
        assertEq(deployment.stagedProposalProcessorPluginRepo, address(0));
    }

    modifier whenInvokingDeployOnce() {
        _;
    }

    function test_GivenNoPriorDeploymentOnTheFactory()
        external
        whenInvokingDeployOnce
    {
        // It Should emit an event with the factory address
        vm.expectEmit(true, true, true, true);
        emit ProtocolFactory.ProtocolDeployed(factory);

        // Deploy the protocol
        factory.deployOnce();

        // It The deployment addresses are filled with the new contracts
        deployment = factory.getDeployment();
        assertNotEq(deployment.daoFactory, address(0));
        assertNotEq(deployment.pluginRepoFactory, address(0));
        assertNotEq(deployment.pluginSetupProcessor, address(0));
        assertNotEq(deployment.globalExecutor, address(0)); // Should be the base address provided
        assertNotEq(deployment.placeholderSetup, address(0)); // Should be the base address provided
        assertNotEq(deployment.daoRegistry, address(0));
        assertNotEq(deployment.pluginRepoRegistry, address(0));
        assertNotEq(deployment.managementDao, address(0));
        assertNotEq(deployment.managementDaoMultisig, address(0));
        assertNotEq(deployment.ensRegistry, address(0));
        assertNotEq(deployment.daoSubdomainRegistrar, address(0));
        assertNotEq(deployment.pluginSubdomainRegistrar, address(0));
        assertNotEq(deployment.publicResolver, address(0));
        assertNotEq(deployment.adminPluginRepo, address(0));
        assertNotEq(deployment.multisigPluginRepo, address(0));
        assertNotEq(deployment.tokenVotingPluginRepo, address(0));
        assertNotEq(deployment.stagedProposalProcessorPluginRepo, address(0));

        // Check a few key implementations match the params
        assertEq(
            deployment.globalExecutor,
            deploymentParams.osxImplementations.globalExecutor
        );
        assertEq(
            deployment.placeholderSetup,
            deploymentParams.osxImplementations.placeholderSetup
        );

        // It Parameters should remain immutable after deployOnce is invoked
        ProtocolFactory.DeploymentParameters memory currentParams = factory
            .getParameters();

        assertEq(
            keccak256(abi.encode(currentParams)),
            keccak256(abi.encode(deploymentParams))
        );

        // It The used ENS setup matches the given parameters
        ENS ens = ENS(deployment.ensRegistry);
        ENSSubdomainRegistrar daoRegistrar = ENSSubdomainRegistrar(
            deployment.daoSubdomainRegistrar
        );
        ENSSubdomainRegistrar pluginRegistrar = ENSSubdomainRegistrar(
            deployment.pluginSubdomainRegistrar
        );
        IResolver resolver = IResolver(deployment.publicResolver); // Assuming PublicResolver implements this basic func

        // Owner of the registry contract itself is the Management DAO
        assertEq(
            ens.owner(bytes32(0)),
            deployment.managementDao,
            "Registry root owner mismatch"
        );

        // 2. Check Root Domain Ownership
        assertEq(
            ens.owner(daoRootNode),
            deployment.managementDao,
            "DAO root domain owner mismatch"
        );
        assertEq(
            ens.owner(pluginRootNode),
            deployment.managementDao,
            "Plugin root domain owner mismatch"
        );

        // 3. Check DAO Registrar State
        assertEq(
            address(daoRegistrar.dao()),
            deployment.managementDao,
            "DAO Registrar: DAO mismatch"
        );
        assertEq(
            address(daoRegistrar.ens()),
            deployment.ensRegistry,
            "DAO Registrar: ENS mismatch"
        );
        assertEq(
            daoRegistrar.node(),
            daoRootNode,
            "DAO Registrar: Root node mismatch"
        );

        // 4. Check Plugin Registrar State
        assertEq(
            address(pluginRegistrar.dao()),
            deployment.managementDao,
            "Plugin Registrar: DAO mismatch"
        );
        assertEq(
            address(pluginRegistrar.ens()),
            deployment.ensRegistry,
            "Plugin Registrar: ENS mismatch"
        );
        assertEq(
            pluginRegistrar.node(),
            pluginRootNode,
            "Plugin Registrar: Root node mismatch"
        );

        // 5. Check Management DAO ENS Resolution
        assertEq(
            ens.owner(managementDaoNode),
            deployment.daoSubdomainRegistrar,
            "Management DAO ENS node owner mismatch"
        );
        assertEq(
            ens.resolver(managementDaoNode),
            deployment.publicResolver,
            "Management DAO ENS node resolver mismatch"
        );
        // Check resolution via the resolver itself
        assertEq(
            resolver.addr(managementDaoNode),
            deployment.managementDao,
            "Management DAO ENS resolver addr() mismatch"
        );

        // 6. Check Operator Approvals on ENS Registry granted by Management DAO
        // The factory executes actions via the Mgmt DAO to grant these during setup.
        assertTrue(
            ens.isApprovedForAll(
                deployment.managementDao,
                deployment.daoSubdomainRegistrar
            ),
            "DAO Registrar not approved operator"
        );
        assertTrue(
            ens.isApprovedForAll(
                deployment.managementDao,
                deployment.pluginSubdomainRegistrar
            ),
            "Plugin Registrar not approved operator"
        );
        // Check DAORegistry/PluginRepoRegistry permissions elsewhere if needed

        // 7. Check Implementation Address (optional sanity check)
        address daoRegImpl = address(
            uint160(
                uint256(
                    vm.load(
                        deployment.daoSubdomainRegistrar,
                        bytes32(
                            uint256(
                                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
                            )
                        )
                    )
                )
            )
        ); // ERC1967 Impl Slot
        assertEq(
            daoRegImpl,
            deploymentParams.osxImplementations.ensSubdomainRegistrarBase,
            "DAO Registrar Impl mismatch"
        );
        address pluginRegImpl = address(
            uint160(
                uint256(
                    vm.load(
                        deployment.pluginSubdomainRegistrar,
                        bytes32(
                            uint256(
                                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
                            )
                        )
                    )
                )
            )
        ); // ERC1967 Impl Slot
        assertEq(
            pluginRegImpl,
            deploymentParams.osxImplementations.ensSubdomainRegistrarBase,
            "Plugin Registrar Impl mismatch"
        );
    }

    function test_RevertGiven_TheFactoryAlreadyMadeADeployment()
        external
        whenInvokingDeployOnce
    {
        // It Should revert
        // It Parameters should remain unchanged
        // It Deployment addresses should remain unchanged
        vm.skip(true);
    }

    modifier givenAProtocolDeployment() {
        factory.deployOnce();
        deployment = factory.getDeployment();

        _;
    }

    function test_WhenCallingGetParameters() external givenAProtocolDeployment {
        // It Should return the given values
        vm.skip(true);
    }

    function test_WhenCallingGetDeployment() external givenAProtocolDeployment {
        // It Should return the right values
        vm.skip(true);
    }

    function test_WhenUsingTheDAOFactory() external givenAProtocolDeployment {
        // It Should deploy a valid DAO and register it
        // It New DAOs should have the right permissions on themselves
        // It New DAOs should be resolved from the requested ENS subdomain
        vm.skip(true);
    }

    function test_WhenUsingThePluginRepoFactory()
        external
        givenAProtocolDeployment
    {
        // It Should deploy a valid PluginRepo and register it
        // It The maintainer can publish new versions
        // It The plugin repo should be resolved from the requested ENS subdomain
        vm.skip(true);
    }

    function test_WhenUsingTheManagementDAO()
        external
        givenAProtocolDeployment
    {
        // It Should be able to publish new core plugin versions
        // It Should have a multisig with the given members and settings
        vm.skip(true);
    }

    function test_WhenPreparingAnAdminPluginInstallation()
        external
        givenAProtocolDeployment
    {
        // It should complete normally
        vm.skip(true);
    }

    function test_WhenApplyingAnAdminPluginInstallation()
        external
        givenAProtocolDeployment
    {
        // It should allow the admin to execute on the DAO
        vm.skip(true);
    }

    function test_WhenPreparingAMultisigPluginInstallation()
        external
        givenAProtocolDeployment
    {
        // It should complete normally
        vm.skip(true);
    }

    function test_WhenApplyingAMultisigPluginInstallation()
        external
        givenAProtocolDeployment
    {
        // It should allow its members to approve and execute on the DAO
        vm.skip(true);
    }

    function test_WhenPreparingATokenVotingPluginInstallation()
        external
        givenAProtocolDeployment
    {
        // It should complete normally
        vm.skip(true);
    }

    function test_WhenApplyingATokenVotingPluginInstallation()
        external
        givenAProtocolDeployment
    {
        // It should allow its members to approve and execute on the DAO
        vm.skip(true);
    }

    function test_WhenPreparingAnSPPPluginInstallation()
        external
        givenAProtocolDeployment
    {
        // It should complete normally
        vm.skip(true);
    }

    function test_WhenApplyingAnSPPPluginInstallation()
        external
        givenAProtocolDeployment
    {
        // It should allow its bodies to execute on the DAO
        vm.skip(true);
    }
}
