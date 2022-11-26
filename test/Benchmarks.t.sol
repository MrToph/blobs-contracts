// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";
import {Blobs} from "../src/Blobs.sol";
import {RandProvider} from "../src/utils/rand/RandProvider.sol";
import {ChainlinkV1RandProvider} from "../src/utils/rand/ChainlinkV1RandProvider.sol";
import {Goo} from "../src/Goo.sol";
import {LinkToken} from "./utils/mocks/LinkToken.sol";
import {VRFCoordinatorMock} from "chainlink/v0.8/mocks/VRFCoordinatorMock.sol";

contract BenchmarksTest is DSTest {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    Blobs private blobs;
    VRFCoordinatorMock private vrfCoordinator;
    LinkToken private linkToken;
    RandProvider private randProvider;
    Goo private goo;

    bytes32 private keyHash;
    uint256 private fee;

    function setUp() public {
        vm.warp(1); // Otherwise mintStart will be set to 0 and brick pages.mintFromGoo(type(uint256).max)

        utils = new Utilities();
        users = utils.createUsers(5);
        linkToken = new LinkToken();
        vrfCoordinator = new VRFCoordinatorMock(address(linkToken));

        //blobs contract will be deployed after 2 contract deploys
        address blobAddress = utils.predictContractAddress(address(this), 2);

        randProvider = new ChainlinkV1RandProvider(
            Blobs(blobAddress),
            address(vrfCoordinator),
            address(linkToken),
            keyHash,
            fee
        );

        goo = new Goo(blobAddress, address(0xDEAD));

        blobs = new Blobs(
            keccak256(abi.encodePacked(users[0])),
            block.timestamp,
            goo,
            address(0xBEEF),
            address(0xBEEF),
            randProvider,
            "base",
            ""
        );

        vm.prank(address(blobs));
        goo.mintForBlobs(address(this), type(uint192).max);

        // approve contract
        goo.approve(address(blobs), type(uint256).max);
        mintBlobToAddress(address(this), 1000);

        vm.warp(block.timestamp + 30 days);

        bytes32 requestId = blobs.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked("seed")));
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));
    }

    function testBlobPrice() public view {
        blobs.blobPrice();
    }

    function testMintBlob() public {
        blobs.mintFromGoo(type(uint256).max);
    }

    function testTransferBlob() public {
        blobs.transferFrom(address(this), address(0xBEEF), 1);
    }

    function testRevealBlobs() public {
        blobs.revealBlobs(100);
    }

    function testMintReservedBlobs() public {
        blobs.mintReservedBlobs(1);
    }

    function mintBlobToAddress(address addr, uint256 num) internal {
        for (uint256 i = 0; i < num; ++i) {
            vm.startPrank(address(blobs));
            goo.mintForBlobs(addr, blobs.blobPrice());
            vm.stopPrank();

            vm.prank(addr);
            blobs.mintFromGoo(type(uint256).max);
        }
    }
}
