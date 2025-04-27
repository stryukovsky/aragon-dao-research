// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {AragonTest} from "./helpers/AragonTest.sol";
import {ProtocolFactoryBuilder} from "./helpers/ProtocolFactoryBuilder.sol";
import {ProtocolFactory} from "../src/ProtocolFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DummySetup} from "./helpers/DummySetup.sol";

// OSx Imports
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO, Action} from "@aragon/osx/core/dao/DAO.sol";
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
import {GovernanceWrappedERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceWrappedERC20.sol";
import {MajorityVotingBase} from "@aragon/token-voting-plugin/MajorityVotingBase.sol";
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

    modifier whenInvokingDeployOnce() {
        _;
    }

    modifier givenAProtocolDeployment() {
        factory.deployOnce();
        deployment = factory.getDeployment();
        deploymentParams = builder.getDeploymentParams();

        // Ensure deployment actually happened for modifier sanity
        assertNotEq(deployment.daoFactory, address(0));

        _;
    }

    function test_WhenUsingTheManagementDAO()
        external
        givenAProtocolDeployment
    {
        Multisig multisig = Multisig(deployment.managementDaoMultisig);
        PluginRepo adminRepo = PluginRepo(deployment.adminPluginRepo);

        // It Should have a multisig with the given members and settings
        assertEq(
            multisig.addresslistLength(),
            mgmtDaoMembers.length,
            "Member count mismatch"
        );
        for (uint i = 0; i < mgmtDaoMembers.length; i++) {
            assertTrue(
                multisig.isListed(mgmtDaoMembers[i]),
                "Member address mismatch"
            );
        }
        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        assertTrue(onlyListed, "OnlyListed should be true");
        assertEq(
            minApprovals,
            uint16(deploymentParams.managementDao.minApprovals),
            "Min approvals mismatch"
        );

        // It Should be able to publish new core plugin versions (via multisig)
        DummySetup dummySetup = new DummySetup();
        uint8 targetRelease = deploymentParams.corePlugins.adminPlugin.release;
        bytes memory buildMeta = bytes("ipfs://new-admin-build");
        bytes memory releaseMeta = bytes("ipfs://new-admin-release"); // Usually same for build
        bytes memory actionData = abi.encodeCall(
            PluginRepo.createVersion,
            (
                targetRelease, // target release
                address(dummySetup), // new setup implementation
                buildMeta,
                releaseMeta
            )
        );

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: deployment.adminPluginRepo,
            value: 0,
            data: actionData
        });

        // Move 1 block forward to avoid ProposalCreationForbidden()
        vm.roll(block.number + 1);

        // Create proposal (Alice proposes)
        vm.prank(alice);
        uint256 proposalId = multisig.createProposal(
            bytes("ipfs://prop-new-admin-version"),
            actions,
            0, // startdate
            uint64(block.timestamp + 100), // enddate
            bytes("")
        );
        // Move 1 block forward to avoid missing the snapshot block
        vm.roll(block.number + 1);

        assertTrue(multisig.canApprove(proposalId, alice), "Cannot approve");
        vm.prank(alice);
        multisig.approve(proposalId, false);

        // Approve (Bob approves, reaching minApprovals = 2)
        vm.prank(bob);
        multisig.approve(proposalId, false);

        uint256 buildCountBefore = adminRepo.buildCount(targetRelease);

        // Execute (Carol executes)
        assertTrue(
            multisig.canExecute(proposalId),
            "Proposal should be executable"
        );
        vm.prank(carol);
        multisig.execute(proposalId);

        uint256 buildCountAfter = adminRepo.buildCount(targetRelease);
        assertEq(
            buildCountBefore + 1,
            buildCountAfter,
            "Should have increased hte buildCount"
        );

        // Verify new version
        PluginRepo.Version memory latestVersion = adminRepo.getLatestVersion(
            targetRelease
        );
        assertEq(
            latestVersion.pluginSetup,
            address(dummySetup),
            "New version setup mismatch"
        );
        assertEq(
            latestVersion.buildMetadata,
            buildMeta,
            "New version build meta mismatch"
        );
    }

    // Helpers

    function getImplementation(address proxy) private returns (address) {
        return
            address(
                uint160(
                    uint256(
                        vm.load(
                            proxy,
                            bytes32(
                                uint256(
                                    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
                                )
                            )
                        )
                    )
                )
            );
    }
}
