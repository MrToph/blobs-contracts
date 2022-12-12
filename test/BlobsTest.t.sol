// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/Test.sol";
import {VRFCoordinatorMock} from "chainlink/v0.8/mocks/VRFCoordinatorMock.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {MockERC1155} from "solmate/test/utils/mocks/MockERC1155.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {fromDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {Pages} from "art-gobblers/Pages.sol";
import {ArtGobblers} from "art-gobblers/ArtGobblers.sol";
import {Goo} from "art-gobblers/Goo.sol";

import {Blobs, FixedPointMathLib} from "../src/Blobs.sol";
import {GobblersTreasury} from "../src/GobblersTreasury.sol";
import {BlobReserve} from "../src/utils/BlobReserve.sol";
import {RandProvider} from "../src/utils/rand/RandProvider.sol";
import {ChainlinkV1RandProvider} from "../src/utils/rand/ChainlinkV1RandProvider.sol";
import {LinkToken} from "./utils/mocks/LinkToken.sol";
import {MockArtGobblers} from "./MockArtGobblers.sol";

/// @notice Unit test for Art Blob Contract.
contract BlobsTest is DSTestPlus {
    using LibString for uint256;

    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    Blobs internal blobs;
    VRFCoordinatorMock internal vrfCoordinator;
    LinkToken internal linkToken;
    Goo internal goo;
    MockArtGobblers internal gobblers;
    BlobReserve internal team;
    GobblersTreasury internal treasury;
    RandProvider internal randProvider;
    address internal constant timelock = address(0x2007);

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

        //blobs contract will be deployed after 5 contract deploys
        address blobAddress = utils.predictContractAddress(address(this), 5);

        team = new BlobReserve(Blobs(blobAddress), address(this));
        randProvider = new ChainlinkV1RandProvider(
            Blobs(blobAddress),
            address(vrfCoordinator),
            address(linkToken),
            keyHash,
            fee
        );

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
        address salesReceiver = address(treasury);

        blobs = new Blobs(
            keccak256(abi.encodePacked(users[0])),
            block.timestamp,
            goo,
            address(team),
            salesReceiver,
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
                               MINT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that minting from the mintlist before minting starts fails.
    function testMintFromMintlistBeforeMintingStarts() public {
        vm.warp(block.timestamp - 1);

        address user = users[0];
        bytes32[] memory proof;
        vm.prank(user);
        vm.expectRevert(Blobs.MintStartPending.selector);
        blobs.claimBlob(proof);
    }

    /// @notice Test that you can mint from mintlist successfully.
    function testMintFromMintlist() public {
        address user = users[0];
        bytes32[] memory proof;
        vm.prank(user);
        blobs.claimBlob(proof);
        // verify blob ownership
        assertEq(blobs.ownerOf(1), user);
        assertEq(blobs.balanceOf(user), 1);
    }

    /// @notice Test that minting from the mintlist twice fails.
    function testMintingFromMintlistTwiceFails() public {
        address user = users[0];
        bytes32[] memory proof;
        vm.startPrank(user);
        blobs.claimBlob(proof);

        vm.expectRevert(Blobs.AlreadyClaimed.selector);
        blobs.claimBlob(proof);
    }

    /// @notice Test that an invalid mintlist proof reverts.
    function testMintNotInMintlist() public {
        bytes32[] memory proof;
        vm.expectRevert(Blobs.InvalidProof.selector);
        blobs.claimBlob(proof);
    }

    /// @notice Test that you can successfully mint from goo.
    function testMintFromGoo() public {
        uint256 cost = blobs.blobPrice();
        vm.prank(address(gobblers));
        goo.mintForGobblers(users[0], cost);

        vm.prank(users[0]);
        blobs.mintFromGoo(type(uint256).max);
        assertEq(blobs.ownerOf(1), users[0]);
        // sale proceedings go to treasury and are deposited into goo tank
        assertEq(gobblers.gooBalance(address(treasury)), cost);
    }

    /// @notice Test that trying to mint with insufficient balance reverts.
    function testMintInsufficientBalance() public {
        vm.prank(users[0]);
        vm.expectRevert(stdError.arithmeticError);
        blobs.mintFromGoo(type(uint256).max);
    }

    /// @notice Test that if mint price exceeds max it reverts.
    function testMintPriceExceededMax() public {
        uint256 cost = blobs.blobPrice();
        vm.prank(address(gobblers));
        goo.mintForGobblers(users[0], cost);

        vm.prank(users[0]);
        vm.expectRevert(abi.encodeWithSelector(Blobs.PriceExceededMax.selector, cost));
        blobs.mintFromGoo(cost - 1);
    }

    /// @notice Test that initial blob price is what we expect.
    function testInitialBlobPrice() public {
        // Warp to the target sale time so that the blob price equals the target price.
        vm.warp(block.timestamp + fromDaysWadUnsafe(blobs.getTargetSaleTime(1e18)));

        uint256 cost = blobs.blobPrice();
        assertRelApproxEq(cost, uint256(blobs.targetPrice()), 0.00001e18);
    }

    /// @notice Test that minting reserved blobs fails if there are no mints.
    function testMintReservedBlobsFailsWithNoMints() public {
        vm.expectRevert(Blobs.ReserveImbalance.selector);
        blobs.mintReservedBlobs(1);
    }

    /// @notice Test that reserved blobs can be minted under fair circumstances.
    function testCanMintReserved() public {
        mintBlobToAddress(users[0], 9);

        blobs.mintReservedBlobs(1);
        assertEq(blobs.ownerOf(10), address(team));
        assertEq(blobs.balanceOf(address(team)), 1);
    }

    /// @notice Test multiple reserved blobs can be minted under fair circumstances.
    function testCanMintMultipleReserved() public {
        mintBlobToAddress(users[0], 18);

        blobs.mintReservedBlobs(2);
        assertEq(blobs.ownerOf(19), address(team));
        assertEq(blobs.ownerOf(20), address(team));
        assertEq(blobs.balanceOf(address(team)), 2);
    }

    /// @notice Test minting reserved blobs fails if not enough have blobs been minted.
    function testCantMintTooFastReserved() public {
        mintBlobToAddress(users[0], 18);

        vm.expectRevert(Blobs.ReserveImbalance.selector);
        blobs.mintReservedBlobs(3);
    }

    /// @notice Test minting reserved blobs fails one by one if not enough have blobs been minted.
    function testCantMintTooFastReservedOneByOne() public {
        mintBlobToAddress(users[0], 90);

        // can only mint 10 (10% of 100)
        blobs.mintReservedBlobs(1);
        blobs.mintReservedBlobs(1);
        blobs.mintReservedBlobs(1);
        blobs.mintReservedBlobs(1);
        blobs.mintReservedBlobs(1);
        blobs.mintReservedBlobs(1);
        blobs.mintReservedBlobs(1);
        blobs.mintReservedBlobs(1);
        blobs.mintReservedBlobs(1);
        blobs.mintReservedBlobs(1);

        vm.expectRevert(Blobs.ReserveImbalance.selector);
        blobs.mintReservedBlobs(1);
    }

    /*//////////////////////////////////////////////////////////////
                              PRICING TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test VRGDA behavior when selling at target rate.
    // disabled because we removed the community fund which changes the # blobs minted over time, changing the pricing function
    function xtestPricingBasic() public {
        // VRGDA targets this number of mints at given time.
        uint256 timeDelta = 120 days;
        // chosen such that blobs.getTargetSaleTime(int256(numMint * 1e18))) ~ 120e18
        uint256 numMint = 877;
        vm.warp(block.timestamp + timeDelta);

        for (uint256 i = 0; i < numMint; ++i) {
            vm.startPrank(address(blobs));
            uint256 price = blobs.blobPrice();
            goo.mintForGobblers(users[0], price);
            vm.stopPrank();
            vm.prank(users[0]);
            blobs.mintFromGoo(price);
        }

        uint256 targetPrice = uint256(blobs.targetPrice());
        uint256 finalPrice = blobs.blobPrice();

        // Equal within 3 percent since num mint is rounded from true decimal amount.
        assertRelApproxEq(finalPrice, targetPrice, 0.03e18);
    }

    /// @notice Pricing function should NOT revert when trying to price the last mintable blob.
    function testDoesNotRevertEarly() public view {
        // This is the last blob we expect to mint.
        int256 maxMintable = int256(blobs.MAX_MINTABLE()) * 1e18;
        // This call should NOT revert, since we should have a target date for the last mintable blob.
        blobs.getTargetSaleTime(maxMintable);
    }

    /// @notice Pricing function should revert when trying to price beyond the last mintable blob.
    function testDoesRevertWhenExpected() public {
        // One plus the max number of mintable blobs.
        int256 maxMintablePlusOne = int256(blobs.MAX_MINTABLE() + 1) * 1e18;
        // This call should revert, since there should be no target date beyond max mintable blobs.
        vm.expectRevert("UNDEFINED");
        blobs.getTargetSaleTime(maxMintablePlusOne);
    }

    /*//////////////////////////////////////////////////////////////
                                  URIS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test unminted URI is correct.
    function testUnmintedUri() public {
        hevm.expectRevert("NOT_MINTED");
        blobs.tokenURI(1);
    }

    /// @notice Test that unrevealed URI is correct.
    function testUnrevealedUri() public {
        uint256 blobCost = blobs.blobPrice();
        vm.prank(address(gobblers));
        goo.mintForGobblers(users[0], blobCost);

        vm.prank(users[0]);
        blobs.mintFromGoo(type(uint256).max);
        // assert blob not revealed after mint
        assertTrue(stringEquals(blobs.tokenURI(1), blobs.UNREVEALED_URI()));
    }

    /// @notice Test that revealed URI is correct.
    function testRevealedUri() public {
        mintBlobToAddress(users[0], 1);
        // unrevealed blobs have 0 value attributes
        vm.warp(block.timestamp + 1 days);
        setRandomnessAndReveal(1, "seed");
        (, uint64 expectedIndex) = blobs.getBlobData(1);
        string memory expectedURI = string(abi.encodePacked(blobs.BASE_URI(), uint256(expectedIndex).toString()));
        assertTrue(stringEquals(blobs.tokenURI(1), expectedURI));
    }

    /*//////////////////////////////////////////////////////////////
                                 REVEALS
    //////////////////////////////////////////////////////////////*/

    function testDoesNotAllowRevealingZero() public {
        vm.warp(block.timestamp + 24 hours);
        vm.expectRevert(Blobs.ZeroToBeRevealed.selector);
        blobs.requestRandomSeed();
    }

    /// @notice Cannot request random seed before 24 hours have passed from initial mint.
    function testRevealDelayInitialMint() public {
        mintBlobToAddress(users[0], 1);
        vm.expectRevert(Blobs.RequestTooEarly.selector);
        blobs.requestRandomSeed();
    }

    /// @notice Cannot reveal more blobs than remaining to be revealed.
    function testCannotRevealMoreBlobsThanRemainingToBeRevealed() public {
        mintBlobToAddress(users[0], 1);

        vm.warp(block.timestamp + 24 hours);

        bytes32 requestId = blobs.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked("seed")));
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));

        mintBlobToAddress(users[0], 2);

        vm.expectRevert(abi.encodeWithSelector(Blobs.NotEnoughRemainingToBeRevealed.selector, 1));
        blobs.revealBlobs(2);
    }

    /// @notice Cannot request random seed before 24 hours have passed from last reveal,
    function testRevealDelayRecurring() public {
        // Mint and reveal first blob
        mintBlobToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);
        setRandomnessAndReveal(1, "seed");
        // Attempt reveal before 24 hours have passed
        mintBlobToAddress(users[0], 1);
        vm.expectRevert(Blobs.RequestTooEarly.selector);
        blobs.requestRandomSeed();
    }

    /// @notice Test that seed can't be set without first revealing pending blobs.
    function testCantSetRandomSeedWithoutRevealing() public {
        mintBlobToAddress(users[0], 2);
        vm.warp(block.timestamp + 1 days);
        setRandomnessAndReveal(1, "seed");
        vm.warp(block.timestamp + 1 days);
        // should fail since there is one remaining blob to be revealed with seed
        vm.expectRevert(Blobs.RevealsPending.selector);
        setRandomnessAndReveal(1, "seed");
    }

    /// @notice Test that revevals work as expected
    function testMultiReveal() public {
        mintBlobToAddress(users[0], 100);
        // first 100 blobs should be unrevealed
        for (uint256 i = 1; i <= 100; ++i) {
            assertEq(blobs.tokenURI(i), blobs.UNREVEALED_URI());
        }

        vm.warp(block.timestamp + 1 days); // can only reveal every 24 hours

        setRandomnessAndReveal(50, "seed");
        // first 50 blobs should now be revealed
        for (uint256 i = 1; i <= 50; ++i) {
            assertTrue(!stringEquals(blobs.tokenURI(i), blobs.UNREVEALED_URI()));
        }
        // and next 50 should remain unrevealed
        for (uint256 i = 51; i <= 100; ++i) {
            assertTrue(stringEquals(blobs.tokenURI(i), blobs.UNREVEALED_URI()));
        }
    }

    function testCannotReuseSeedForReveal() public {
        // first mint and reveal.
        mintBlobToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);
        setRandomnessAndReveal(1, "seed");
        // seed used for first reveal.
        (uint64 firstSeed,,,,) = blobs.blobRevealsData();
        // second mint.
        mintBlobToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);
        blobs.requestRandomSeed();
        // seed we want to use for second reveal.
        (uint64 secondSeed,,,,) = blobs.blobRevealsData();
        // verify that we are trying to use the same seed.
        assertEq(firstSeed, secondSeed);
        // try to reveal with same seed, which should fail.
        vm.expectRevert(Blobs.SeedPending.selector);
        blobs.revealBlobs(1);
        assertTrue(true);
    }

    /*//////////////////////////////////////////////////////////////
                           LONG-RUNNING TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check that max supply is mintable
    function testLongRunningMintMaxFromGoo() public {
        uint256 maxMintableWithGoo = blobs.MAX_MINTABLE();

        for (uint256 i = 0; i < maxMintableWithGoo; ++i) {
            vm.warp(block.timestamp + 1 days);
            uint256 cost = blobs.blobPrice();
            vm.prank(address(blobs));
            goo.mintForGobblers(users[0], cost);
            vm.prank(users[0]);
            blobs.mintFromGoo(type(uint256).max);
        }
    }

    /// @notice Check that minting beyond max supply should revert.
    function testLongRunningMintMaxFromGooRevert() public {
        uint256 maxMintableWithGoo = blobs.MAX_MINTABLE();

        for (uint256 i = 0; i < maxMintableWithGoo + 1; ++i) {
            vm.warp(block.timestamp + 1 days);

            if (i == maxMintableWithGoo) vm.expectRevert("UNDEFINED");
            uint256 cost = blobs.blobPrice();

            vm.prank(address(blobs));
            goo.mintForGobblers(users[0], cost);
            vm.prank(users[0]);

            if (i == maxMintableWithGoo) vm.expectRevert("UNDEFINED");
            blobs.mintFromGoo(type(uint256).max);
        }
    }

    /// @notice Check that max reserved supplies are mintable.
    function testLongRunningMintMaxReserved() public {
        uint256 maxMintableWithGoo = blobs.MAX_MINTABLE();

        for (uint256 i = 0; i < maxMintableWithGoo; ++i) {
            vm.warp(block.timestamp + 1 days);
            uint256 cost = blobs.blobPrice();
            vm.prank(address(blobs));
            goo.mintForGobblers(users[0], cost);
            vm.prank(users[0]);
            blobs.mintFromGoo(type(uint256).max);
        }

        blobs.mintReservedBlobs(blobs.RESERVED_SUPPLY() / 2);
    }

    /// @notice Check that minting reserves beyond their max supply reverts.
    function testLongRunningMintMaxTeamRevert() public {
        uint256 maxMintableWithGoo = blobs.MAX_MINTABLE();

        for (uint256 i = 0; i < maxMintableWithGoo; ++i) {
            vm.warp(block.timestamp + 1 days);
            uint256 cost = blobs.blobPrice();
            vm.prank(address(blobs));
            goo.mintForGobblers(users[0], cost);
            vm.prank(users[0]);
            blobs.mintFromGoo(type(uint256).max);
        }

        blobs.mintReservedBlobs(blobs.RESERVED_SUPPLY() / 2);

        vm.expectRevert(Blobs.ReserveImbalance.selector);
        blobs.mintReservedBlobs(1);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint a number of blobs to the given address
    function mintBlobToAddress(address addr, uint256 num) internal {
        for (uint256 i = 0; i < num; ++i) {
            vm.startPrank(address(gobblers));
            goo.mintForGobblers(addr, blobs.blobPrice());
            vm.stopPrank();

            uint256 blobsOwnedBefore = blobs.balanceOf(addr);

            vm.prank(addr);
            blobs.mintFromGoo(type(uint256).max);

            assertEq(blobs.balanceOf(addr), blobsOwnedBefore + 1);
        }
    }

    /// @notice Call back vrf with randomness and reveal blobs.
    function setRandomnessAndReveal(uint256 numReveal, string memory seed) internal {
        bytes32 requestId = blobs.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked(seed)));
        // call back from coordinator
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));
        blobs.revealBlobs(numReveal);
    }

    /// @notice Check for string equality.
    function stringEquals(string memory s1, string memory s2) internal pure returns (bool) {
        return keccak256(abi.encodePacked(s1)) == keccak256(abi.encodePacked(s2));
    }
}
