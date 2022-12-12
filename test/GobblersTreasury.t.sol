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

    function testNoMintGobblerMaxBid() public {
        vm.prank(timelock);
        treasury.setMintAveragingDays(type(uint80).max);

        uint256 gobblerPrice = gobblers.gobblerPrice();
        vm.prank(address(gobblers));
        goo.mintForGobblers(address(treasury), gobblerPrice - 1);
        treasury.addGoo();


        vm.expectRevert(abi.encodeWithSelector(GobblersTreasury.MintNotEnoughGoo.selector, gobblerPrice - 1, gobblerPrice));
        treasury.mintGobbler();
    }

    function testMintGobblerMaxBid() public {
        vm.prank(timelock);
        treasury.setMintAveragingDays(type(uint80).max);

        uint256 gobblerPrice = gobblers.gobblerPrice();
        vm.prank(address(gobblers));
        goo.mintForGobblers(address(treasury), gobblerPrice);
        treasury.addGoo();

        treasury.mintGobbler();
        uint256 gobblersMinted = gobblers.balanceOf(address(treasury));
        assertEq(gobblersMinted, 1, "Gobblers minted");
        assertEq(gobblers.gooBalance(address(treasury)), 0, "did not use up all goo");
    }

    function testNoMintGobblerTimeAveraged() public {
        gobblers.mintGobblerExposed(address(treasury), 100); // multiple of 100
        vm.prank(timelock);
        treasury.setMintAveragingDays(49e18);

        uint256 gobblerPrice = gobblers.gobblerPrice();
        console.log(gobblerPrice);
        assertEq(gobblerPrice, 73.013654753028651285e18, "unexpected gobbler start mint price");

        vm.prank(address(gobblers));
        goo.mintForGobblers(address(treasury), gobblerPrice);
        treasury.addGoo();

        vm.expectRevert(abi.encodeWithSelector(GobblersTreasury.MintNotProfitable.selector, 0xd9ce521aee25f06e43d, 0xd99bd3545182bd30000));
        treasury.mintGobbler();
    }

    function testMintGobblerTimeAveraged() public {
        gobblers.mintGobblerExposed(address(treasury), 100); // multiple of 100
        vm.prank(timelock);
        // we end up with more goo after 50 days if we mint now and have a position of (100 + X multiple, 0 goo) compared to holding the initial position (100, gobblerPrice goo)
        treasury.setMintAveragingDays(50e18);

        uint256 gobblerPrice = gobblers.gobblerPrice();
        console.log(gobblerPrice);
        assertEq(gobblerPrice, 73.013654753028651285e18, "unexpected gobbler start mint price");

        vm.prank(address(gobblers));
        goo.mintForGobblers(address(treasury), gobblerPrice);
        treasury.addGoo();

        treasury.mintGobbler();
        uint256 gobblersMinted = gobblers.balanceOf(address(treasury));
        assertEq(gobblersMinted, 2, "Gobblers minted");
    }

    function testMintLegendaryGobbler() public {
        vm.prank(timelock);
        treasury.setMintAveragingDays(type(uint80).max);

        vm.prank(address(gobblers));
        goo.mintForGobblers(address(treasury), 1e50 * 1e18);
        treasury.addGoo();

        // mint 581 to make legendary gobbler spawn
        uint256[] memory gobblerIds = new uint256[](600);
        for(uint256 i = 0; i < gobblerIds.length; i++) {
            gobblerIds[i] = treasury.mintGobbler();
        }

        // just sacrifice legendaryGobblerPrice of them
        uint256 legendaryGobblerPrice = gobblers.legendaryGobblerPrice();
        gobblerIds = new uint256[](legendaryGobblerPrice);
        for(uint256 i = 0; i < legendaryGobblerPrice; i++) {
            gobblerIds[i] = 100 + i;
        }

        uint256 legendaryGobblerId = treasury.mintLegendaryGobbler(gobblerIds);

        assertEq(legendaryGobblerId, 9991, "!legendary gobbler id");
        assertEq(gobblers.ownerOf(legendaryGobblerId), address(treasury), "!legendary gobbler owner");
        vm.expectRevert("NOT_MINTED");
        gobblers.ownerOf(100);
        assertEq(gobblers.ownerOf(99), address(treasury), "!treasury gobbler owner");
    }


    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/
        /// @notice Mint a number of gobblers to the given address
    function mintGobblerToAddress(address addr, uint256 num) internal {
        for (uint256 i = 0; i < num; ++i) {
            vm.startPrank(address(gobblers));
            goo.mintForGobblers(addr, gobblers.gobblerPrice());
            vm.stopPrank();

            uint256 gobblersOwnedBefore = gobblers.balanceOf(addr);

            vm.prank(addr);
            gobblers.mintFromGoo(type(uint256).max, false);

            assertEq(gobblers.balanceOf(addr), gobblersOwnedBefore + 1);
        }
    }
}
