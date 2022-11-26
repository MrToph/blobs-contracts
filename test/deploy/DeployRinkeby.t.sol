// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {DeployRinkeby} from "../../script/deploy/DeployRinkeby.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {Blobs} from "../../src/Blobs.sol";

contract DeployRinkebyTest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    DeployRinkeby deployScript;

    function setUp() public {
        deployScript = new DeployRinkeby();
        deployScript.run();
    }

    /// @notice Test that merkle root was correctly set.
    function testMerkleRoot() public {
        vm.warp(deployScript.mintStart());
        // Use merkle root as user to test simple proof.
        address user = deployScript.root();
        bytes32[] memory proof;
        Blobs blobs = deployScript.blobs();
        vm.prank(user);
        blobs.claimGobbler(proof);
        // Verify gobbler ownership.
        assertEq(blobs.ownerOf(1), user);
    }

    /// @notice Test cold wallet was appropriately set.
    function testColdWallet() public {
        address coldWallet = deployScript.coldWallet();
        address communityOwner = deployScript.teamReserve().owner();
        address teamOwner = deployScript.communityReserve().owner();
        assertEq(coldWallet, communityOwner);
        assertEq(coldWallet, teamOwner);
    }

    /// @notice Test URIs are correctly set.
    function testURIs() public {
        Blobs blobs = deployScript.blobs();
        assertEq(blobs.BASE_URI(), deployScript.gobblerBaseUri());
        assertEq(blobs.UNREVEALED_URI(), deployScript.gobblerUnrevealedUri());
    }
}
