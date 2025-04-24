// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {ENSRegistry} from "@ensdomains/ens-contracts/contracts/registry/ENSRegistry.sol";
import {PublicResolver, INameWrapper} from "@ensdomains/ens-contracts/contracts/resolvers/PublicResolver.sol";

/// @notice This contract offloads the static deployment of the PluginSetupProcessor
contract ENSHelper {
    bytes32 private constant ROOT_NODE = 0x0;
    bytes32 private constant ETH_LABEL_HASH = keccak256("eth");

    /// @notice Perform an ENS Registry deployment, along with a PublicResolver
    /// @param owner The owner of the ENSRegistry's root node and subsequent subnodes
    /// @param daoRootDomain The domain to use for DAO's
    /// @param daoRootDomain The domain to use for plugins
    function deployStatic(
        address owner,
        bytes memory daoRootDomain,
        bytes memory pluginSubdomain
    )
        external
        returns (
            ENSRegistry ensRegistry,
            PublicResolver publicResolver,
            bytes32 DAO_ETH_NODE,
            bytes32 PLUGIN_DAO_ETH_NODE
        )
    {
        bytes32 ETH_NODE;
        bytes32 DAO_LABEL_HASH = keccak256(daoRootDomain);
        bytes32 PLUGIN_DAO_LABEL_HASH = keccak256(pluginSubdomain);

        // ENS Registry and PublicResolver
        ensRegistry = new ENSRegistry();

        publicResolver = new PublicResolver(
            ensRegistry,
            INameWrapper(address(0))
        );

        // The deployer of ENSRegistry becomes the owner of the root node (0x0).

        // Hold temporary ownership to set the resolver

        ETH_NODE = ensRegistry.setSubnodeOwner(
            ROOT_NODE,
            ETH_LABEL_HASH,
            address(this) // owner
        );

        DAO_ETH_NODE = ensRegistry.setSubnodeOwner(
            ETH_NODE,
            DAO_LABEL_HASH,
            address(this) // owner
        );
        ensRegistry.setResolver(DAO_ETH_NODE, address(publicResolver));

        PLUGIN_DAO_ETH_NODE = ensRegistry.setSubnodeOwner(
            DAO_ETH_NODE,
            PLUGIN_DAO_LABEL_HASH,
            address(this) // owner
        );
        ensRegistry.setResolver(PLUGIN_DAO_ETH_NODE, address(publicResolver));

        // Set the final owner (reverse order)
        ensRegistry.setSubnodeOwner(DAO_ETH_NODE, PLUGIN_DAO_LABEL_HASH, owner);
        ensRegistry.setSubnodeOwner(ETH_NODE, DAO_LABEL_HASH, owner);
        ensRegistry.setSubnodeOwner(ROOT_NODE, ETH_LABEL_HASH, owner);
        ensRegistry.setOwner(ROOT_NODE, owner);
    }
}
