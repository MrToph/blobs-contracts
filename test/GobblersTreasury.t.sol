// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Test, stdError} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Utilities} from "./utils/Utilities.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {MockERC1155} from "solmate/test/utils/mocks/MockERC1155.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {fromDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {Goo} from "art-gobblers/Goo.sol";
import {Pages} from "art-gobblers/Pages.sol";

import {MockArtGobblers} from "./MockArtGobblers.sol";
import {GobblersTreasury} from "../src/GobblersTreasury.sol";
import {BlobReserve} from "../src/utils/BlobReserve.sol";
import {RandProvider} from "../src/utils/rand/RandProvider.sol";

enum Support {
    Against,
    For,
    Abstain
}

/// @notice Unit test for Art Blob Contract.
contract GobblersTreasuryTests is Test {
    using LibString for uint256;

    Utilities internal utils;
    address payable[] internal users;

    address internal constant foundersMsig = address(0x13371338);

    Goo internal goo;
    MockArtGobblers private gobblers;
    GobblersTreasury private treasury;
    address internal constant timelock = address(0x2007);

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        goo = new Goo(
            // ArtGobblers:
            utils.predictContractAddress(address(this), 1),
            // Pages:
            address(0xDEAD)
        );

        gobblers = new MockArtGobblers(
            keccak256(abi.encodePacked(address(this))), // merkle tree = this
            block.timestamp,
            goo,
            Pages(address(0xDEAD)), // pages
            address(0xDEAD), // team
            address(0xDEAD), // community
            address(this), // randProvider
            "base",
            ""
        );
        treasury = new GobblersTreasury(
            address(timelock),
            address(gobblers)
        );
    }

    /*//////////////////////////////////////////////////////////////
                               MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function testGobblersTreasury() public {
    }


    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/
}
