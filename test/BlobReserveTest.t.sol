// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/Test.sol";
import {Blobs} from "../src/Blobs.sol";
import {Goo} from "art-gobblers/Goo.sol";
import {BlobReserve} from "../src/utils/BlobReserve.sol";
import {RandProvider} from "../src/utils/rand/RandProvider.sol";
import {ChainlinkV1RandProvider} from "../src/utils/rand/ChainlinkV1RandProvider.sol";
import {LinkToken} from "./utils/mocks/LinkToken.sol";
import {VRFCoordinatorMock} from "chainlink/v0.8/mocks/VRFCoordinatorMock.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {LibString} from "solmate/utils/LibString.sol";

/// @notice Unit test for the Blob Reserve contract.
contract BlobReserveTest is DSTestPlus {
    using LibString for uint256;

    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    Blobs internal blobs;
    VRFCoordinatorMock internal vrfCoordinator;
    LinkToken internal linkToken;
    Goo internal goo;
    BlobReserve internal team;
    BlobReserve internal community;
    RandProvider internal randProvider;

    bytes32 private keyHash;
    uint256 private fee;

    uint256[] ids;

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);
        linkToken = new LinkToken();
        vrfCoordinator = new VRFCoordinatorMock(address(linkToken));

        //blobs contract will be deployed after 4 contract deploys
        address blobAddress = utils.predictContractAddress(address(this), 4);

        team = new BlobReserve(Blobs(blobAddress), address(this));
        community = new BlobReserve(Blobs(blobAddress), address(this));
        randProvider = new ChainlinkV1RandProvider(
            Blobs(blobAddress),
            address(vrfCoordinator),
            address(linkToken),
            keyHash,
            fee
        );

        goo = new Goo(
            // Blobs:
            utils.predictContractAddress(address(this), 1),
            // Pages:
            address(0xDEAD)
        );

        blobs = new Blobs(
            keccak256(abi.encodePacked(users[0])),
            block.timestamp,
            goo,
            address(team),
            address(community),
            randProvider,
            "base",
            ""
        );

        // users approve contract
        for (uint256 i = 0; i < users.length; ++i) {
            vm.prank(users[i]);
            goo.approve(address(blobs), type(uint256).max);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that a reserve can be withdrawn from.
    function testCanWithdraw() public {
        mintBlobToAddress(users[0], 9);

        blobs.mintReservedBlobs(1);

        assertEq(blobs.ownerOf(10), address(team));

        uint256[] memory idsToWithdraw = new uint256[](1);

        idsToWithdraw[0] = 10;
        team.withdraw(address(this), idsToWithdraw);

        assertEq(blobs.ownerOf(10), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint a number of blobs to the given address
    function mintBlobToAddress(address addr, uint256 num) internal {
        for (uint256 i = 0; i < num; ++i) {
            vm.startPrank(address(blobs));
            goo.mintForGobblers(addr, blobs.blobPrice());
            vm.stopPrank();

            vm.prank(addr);
            blobs.mintFromGoo(type(uint256).max);
        }
    }
}
