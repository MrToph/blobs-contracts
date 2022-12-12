// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {DeployGoerli} from "../../script/deploy/DeployGoerli.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {NounsDAOExecutor} from "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOExecutor.sol";
import {NounsDAOProxyV2} from "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOProxyV2.sol";
import {NounsDAOLogicV2} from "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOLogicV2.sol";
import "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOInterfaces.sol";

import {Utilities} from "../utils/Utilities.sol";
import {Blobs} from "../../src/Blobs.sol";

contract DeployGoerliTest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    DeployGoerli internal deployScript;

    function setUp() public {
        utils = new Utilities();

        deployScript = new DeployGoerli();
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
        blobs.claimBlob(proof);
        // Verify blob ownership.
        assertEq(blobs.ownerOf(1), user);
    }

    /// @notice Test cold wallet was appropriately set.
    function testBlobsConfiguration() public {
        address coldWallet = deployScript.teamColdWallet();
        address gobblersTreasury = address(deployScript.gobblersTreasury());

        address blobsTeam = deployScript.blobs().team();
        address blobsSalesRecipient = deployScript.blobs().salesReceiver();

        assertEq(coldWallet, blobsTeam);
        assertEq(gobblersTreasury, blobsSalesRecipient);
        assertEq(address(deployScript.goo()), address(deployScript.blobs().goo()));
    }

    function testGovernanceConfiguration() public {
        NounsDAOExecutor governanceTimelock = deployScript.timelock();
        NounsDAOLogicV2 governanceProxy = deployScript.proxy();

        assertEq(deployScript.gobblersTreasury().owner(), address(governanceTimelock));
        assertEq(governanceTimelock.admin(), address(governanceProxy));
        assertEq(address(governanceProxy.timelock()), address(governanceTimelock));
        assertEq(address(governanceProxy.nouns()), address(deployScript.blobs()));
        assertEq(address(governanceProxy.vetoer()), address(deployScript.teamColdWallet()));
        assertEq(address(governanceProxy.admin()), address(deployScript.teamColdWallet()));
    }

    /// @notice Test URIs are correctly set.
    function testURIs() public {
        Blobs blobs = deployScript.blobs();
        assertEq(blobs.BASE_URI(), deployScript.blobBaseUri());
        assertEq(blobs.UNREVEALED_URI(), deployScript.blobUnrevealedUri());
    }
}
