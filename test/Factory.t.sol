// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {AragonTest} from "./base/AragonTest.sol";

contract FactoryTest is AragonTest {
    function setUp() public {}

    function test_DeployEvent() public {
        vm.skip(true);
    }
}
