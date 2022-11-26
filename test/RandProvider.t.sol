// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/Test.sol";
import {Blobs} from "../src/Blobs.sol";
import {Goo} from "../src/Goo.sol";
import {GobblerReserve} from "../src/utils/GobblerReserve.sol";
import {RandProvider} from "../src/utils/rand/RandProvider.sol";
import {ChainlinkV1RandProvider} from "../src/utils/rand/ChainlinkV1RandProvider.sol";
import {LinkToken} from "./utils/mocks/LinkToken.sol";
import {VRFCoordinatorMock} from "chainlink/v0.8/mocks/VRFCoordinatorMock.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {LibString} from "solmate/utils/LibString.sol";

/// @notice Unit test for the RandProvider contract.
contract RandProviderTest is DSTestPlus {
    using LibString for uint256;

    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    Blobs internal blobs;
    VRFCoordinatorMock internal vrfCoordinator;
    LinkToken internal linkToken;
    Goo internal goo;
    GobblerReserve internal team;
    GobblerReserve internal community;
    RandProvider internal randProvider;

    bytes32 private keyHash;
    uint256 private fee;

    uint256[] ids;

    //chainlink event
    event RandomnessRequest(address indexed sender, bytes32 indexed keyHash, uint256 indexed seed);

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);
        linkToken = new LinkToken();
        vrfCoordinator = new VRFCoordinatorMock(address(linkToken));

        //blobs contract will be deployed after 4 contract deploys
        address gobblerAddress = utils.predictContractAddress(address(this), 4);

        team = new GobblerReserve(Blobs(gobblerAddress), address(this));
        community = new GobblerReserve(Blobs(gobblerAddress), address(this));
        randProvider = new ChainlinkV1RandProvider(
            Blobs(gobblerAddress),
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

    function testRandomnessIsCorrectlyRequested() public {
        mintGobblerToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);

        //we expect a randomnessRequest event to be emitted once the request reaches the VRFCoordinator.
        //we only check that the request comes from the correct address, i.e. the randProvider
        vm.expectEmit(true, false, false, false); // only check the first indexed event (sender address)
        emit RandomnessRequest(address(randProvider), 0, 0);

        blobs.requestRandomSeed();
    }

    function testRandomnessIsFulfilled() public {
        //initially, randomness should be 0
        (uint64 randomSeed,,,,) = blobs.gobblerRevealsData();
        assertEq(randomSeed, 0);
        mintGobblerToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);
        bytes32 requestId = blobs.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked("seed")));
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));
        //randomness from vrf should be set in blobs contract
        (randomSeed,,,,) = blobs.gobblerRevealsData();
        assertEq(randomSeed, uint64(randomness));
    }

    function testOnlyBlobsCanRequestRandomness() public {
        vm.expectRevert(ChainlinkV1RandProvider.NotBlobs.selector);
        randProvider.requestRandomBytes();
    }

    function testRandomnessIsOnlyUpgradableByOwner() public {
        RandProvider newProvider = new ChainlinkV1RandProvider(Blobs(address(0)), address(0), address(0), 0, 0);
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xBEEFBABE));
        blobs.upgradeRandProvider(newProvider);
    }

    function testRandomnessIsNotUpgradableWithPendingSeed() public {
        mintGobblerToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);
        blobs.requestRandomSeed();
        RandProvider newProvider = new ChainlinkV1RandProvider(Blobs(address(0)), address(0), address(0), 0, 0);
        vm.expectRevert(Blobs.SeedPending.selector);
        blobs.upgradeRandProvider(newProvider);
    }

    function testRandomnessIsUpgradable() public {
        mintGobblerToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);
        //initial address is correct
        assertEq(address(blobs.randProvider()), address(randProvider));

        RandProvider newProvider = new ChainlinkV1RandProvider(Blobs(address(0)), address(0), address(0), 0, 0);
        blobs.upgradeRandProvider(newProvider);
        //final address is correct
        assertEq(address(blobs.randProvider()), address(newProvider));
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint a number of blobs to the given address
    function mintGobblerToAddress(address addr, uint256 num) internal {
        for (uint256 i = 0; i < num; ++i) {
            vm.startPrank(address(blobs));
            goo.mintForBlobs(addr, blobs.gobblerPrice());
            vm.stopPrank();

            vm.prank(addr);
            blobs.mintFromGoo(type(uint256).max);
        }
    }
}
