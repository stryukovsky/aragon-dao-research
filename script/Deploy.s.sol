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

import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {MultisigSetup} from "@aragon/multisig-plugin/MultisigSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting-plugin/TokenVotingSetup.sol";
import {GovernanceERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceWrappedERC20.sol";
import {StagedProposalProcessorSetup} from "@aragon/staged-proposal-processor-plugin/StagedProposalProcessorSetup.sol";

import {ProtocolFactory} from "../src/ProtocolFactory.sol";

/// @notice This local script triggers a full deploy of OSx, along with the core Aragon plugins and the Management DAO
/// @dev No privileged actions are performed within this file. All of them take place within the ProtocolFactory contract, on-chain.
/// @dev Given that deploying the factory with all contracts embedded would hit the gas limit, the deployment has two stages:
/// @dev 1) Deploy the raw contracts and store their addresses locally (this file)
/// @dev 2) Deploy the factory with the addresses above and tell it to orchestrate the protocol deployment
contract DeployScript is Script {
    DAO dao;
    DAORegistry daoRegistry;
    PluginRepo pluginRepo;
    PluginRepoRegistry pluginRepoRegistry;
    PlaceholderSetup placeholderSetup;
    ENSSubdomainRegistrar ensSubdomainRegistrar;
    GlobalExecutor globalExecutor;

    AdminSetup adminSetup;
    MultisigSetup multisigSetup;
    TokenVotingSetup tokenVotingSetup;
    StagedProposalProcessorSetup stagedProposalProcessorSetup;

    ProtocolFactory factory;

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
        deployAdminSetup();
        deployMultisigSetup();
        deployTokenVotingSetup();
        deployStagedProposalProcessorSetup();

        // Factory call
        factory = new ProtocolFactory(getFactoryParams());
        factory.deployOnce();
    }

    // Internal helpers

    function deployOSxImplementations() internal {
        /// @dev Deploy implementations with empty values. They will be used to create proxies.
        dao = new DAO();
        daoRegistry = new DAORegistry();
        pluginRepo = new PluginRepo();
        pluginRepoRegistry = new PluginRepoRegistry();
        placeholderSetup = new PlaceholderSetup();
        ensSubdomainRegistrar = new ENSSubdomainRegistrar();
        globalExecutor = new GlobalExecutor();

        /// @dev The DAOFactory, PluginRepoFactory and PluginSetupProcessor are static.
        /// @dev These contracts will be deployed by the Protocol Factory.
    }

    function deployAdminSetup() internal {
        adminSetup = new AdminSetup();
    }

    function deployMultisigSetup() internal {
        multisigSetup = new MultisigSetup();
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
    }

    function deployStagedProposalProcessorSetup() internal {
        stagedProposalProcessorSetup = new StagedProposalProcessorSetup();
    }

    function getFactoryParams()
        internal
        view
        returns (ProtocolFactory.DeploymentParameters memory params)
    {
        params = ProtocolFactory.DeploymentParameters({
            osxImplementations: ProtocolFactory.OSxImplementations({
                dao: dao,
                daoRegistry: daoRegistry,
                pluginRepo: pluginRepo,
                pluginRepoRegistry: pluginRepoRegistry,
                placeholderSetup: placeholderSetup,
                ensSubdomainRegistrar: ensSubdomainRegistrar,
                globalExecutor: globalExecutor
            }),
            pluginSetups: ProtocolFactory.PluginSetups({
                adminSetup: adminSetup,
                multisigSetup: multisigSetup,
                tokenVotingSetup: tokenVotingSetup,
                stagedProposalProcessorSetup: stagedProposalProcessorSetup
            })
        });
    }
}
