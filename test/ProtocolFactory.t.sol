// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {AragonTest} from "./base/AragonTest.sol";
import {ProtocolFactory} from "../src/ProtocolFactory.sol";
import {ProtocolFactoryBuilder} from "./builders/ProtocolFactoryBuilder.sol";

contract ProtocolFactoryTest is AragonTest {
    ProtocolFactoryBuilder builder;

    ProtocolFactory factory;
    ProtocolFactory.Deployment deployment;

    function setUp() public {
        builder = new ProtocolFactoryBuilder();
        factory = builder.build();
    }

    function test_WhenDeployingTheProtocolFactory() external {
        // It getParameters should return the exact same parameters as provided to the constructor
        // It Parameters should remain immutable after deployOnce is invoked
        vm.skip(true);
    }

    modifier whenInvokingDeployOnce() {
        _;
    }

    function test_GivenNoPriorDeploymentOnTheFactory()
        external
        whenInvokingDeployOnce
    {
        // It Should emit an event with the factory address
        // It The used ENS setup matches the given parameters
        // It The deployment addresses are filled with the new contracts
        vm.skip(true);
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
