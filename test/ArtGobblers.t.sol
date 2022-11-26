// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/Test.sol";
import {ArtGobblers, FixedPointMathLib} from "../src/ArtGobblers.sol";
import {Goo} from "../src/Goo.sol";
import {GobblerReserve} from "../src/utils/GobblerReserve.sol";
import {RandProvider} from "../src/utils/rand/RandProvider.sol";
import {ChainlinkV1RandProvider} from "../src/utils/rand/ChainlinkV1RandProvider.sol";
import {LinkToken} from "./utils/mocks/LinkToken.sol";
import {VRFCoordinatorMock} from "chainlink/v0.8/mocks/VRFCoordinatorMock.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {MockERC1155} from "solmate/test/utils/mocks/MockERC1155.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {fromDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

/// @notice Unit test for Art Gobbler Contract.
contract ArtGobblersTest is DSTestPlus {
    using LibString for uint256;

    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    ArtGobblers internal gobblers;
    VRFCoordinatorMock internal vrfCoordinator;
    LinkToken internal linkToken;
    Goo internal goo;
    GobblerReserve internal team;
    GobblerReserve internal community;
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

        //gobblers contract will be deployed after 4 contract deploys
        address gobblerAddress = utils.predictContractAddress(address(this), 4);

        team = new GobblerReserve(ArtGobblers(gobblerAddress), address(this));
        community = new GobblerReserve(ArtGobblers(gobblerAddress), address(this));
        randProvider = new ChainlinkV1RandProvider(
            ArtGobblers(gobblerAddress),
            address(vrfCoordinator),
            address(linkToken),
            keyHash,
            fee
        );

        goo = new Goo(
            // Gobblers:
            utils.predictContractAddress(address(this), 1),
            // Pages:
            address(0xDEAD)
        );

        gobblers = new ArtGobblers(
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
            goo.approve(address(gobblers), type(uint256).max);
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
        vm.expectRevert(ArtGobblers.MintStartPending.selector);
        gobblers.claimGobbler(proof);
    }

    /// @notice Test that you can mint from mintlist successfully.
    function testMintFromMintlist() public {
        address user = users[0];
        bytes32[] memory proof;
        vm.prank(user);
        gobblers.claimGobbler(proof);
        // verify gobbler ownership
        assertEq(gobblers.ownerOf(1), user);
        assertEq(gobblers.balanceOf(user), 1);
    }

    /// @notice Test that minting from the mintlist twice fails.
    function testMintingFromMintlistTwiceFails() public {
        address user = users[0];
        bytes32[] memory proof;
        vm.startPrank(user);
        gobblers.claimGobbler(proof);

        vm.expectRevert(ArtGobblers.AlreadyClaimed.selector);
        gobblers.claimGobbler(proof);
    }

    /// @notice Test that an invalid mintlist proof reverts.
    function testMintNotInMintlist() public {
        bytes32[] memory proof;
        vm.expectRevert(ArtGobblers.InvalidProof.selector);
        gobblers.claimGobbler(proof);
    }

    /// @notice Test that you can successfully mint from goo.
    function testMintFromGoo() public {
        uint256 cost = gobblers.gobblerPrice();
        vm.prank(address(gobblers));
        goo.mintForGobblers(users[0], cost);
        vm.prank(users[0]);
        gobblers.mintFromGoo(type(uint256).max);
        assertEq(gobblers.ownerOf(1), users[0]);
    }

    /// @notice Test that trying to mint with insufficient balance reverts.
    function testMintInsufficientBalance() public {
        vm.prank(users[0]);
        vm.expectRevert(stdError.arithmeticError);
        gobblers.mintFromGoo(type(uint256).max);
    }

    /// @notice Test that if mint price exceeds max it reverts.
    function testMintPriceExceededMax() public {
        uint256 cost = gobblers.gobblerPrice();
        vm.prank(address(gobblers));
        goo.mintForGobblers(users[0], cost);
        vm.prank(users[0]);
        vm.expectRevert(abi.encodeWithSelector(ArtGobblers.PriceExceededMax.selector, cost));
        gobblers.mintFromGoo(cost - 1);
    }

    /// @notice Test that initial gobbler price is what we expect.
    function testInitialGobblerPrice() public {
        // Warp to the target sale time so that the gobbler price equals the target price.
        vm.warp(block.timestamp + fromDaysWadUnsafe(gobblers.getTargetSaleTime(1e18)));

        uint256 cost = gobblers.gobblerPrice();
        assertRelApproxEq(cost, uint256(gobblers.targetPrice()), 0.00001e18);
    }

    /// @notice Test that minting reserved gobblers fails if there are no mints.
    function testMintReservedGobblersFailsWithNoMints() public {
        vm.expectRevert(ArtGobblers.ReserveImbalance.selector);
        gobblers.mintReservedGobblers(1);
    }

    /// @notice Test that reserved gobblers can be minted under fair circumstances.
    function testCanMintReserved() public {
        mintGobblerToAddress(users[0], 8);

        gobblers.mintReservedGobblers(1);
        assertEq(gobblers.ownerOf(9), address(team));
        assertEq(gobblers.ownerOf(10), address(community));
        assertEq(gobblers.balanceOf(address(team)), 1);
        assertEq(gobblers.balanceOf(address(community)), 1);
    }

    /// @notice Test multiple reserved gobblers can be minted under fair circumstances.
    function testCanMintMultipleReserved() public {
        mintGobblerToAddress(users[0], 18);

        gobblers.mintReservedGobblers(2);
        assertEq(gobblers.ownerOf(19), address(team));
        assertEq(gobblers.ownerOf(20), address(team));
        assertEq(gobblers.ownerOf(21), address(community));
        assertEq(gobblers.ownerOf(22), address(community));
        assertEq(gobblers.balanceOf(address(team)), 2);
        assertEq(gobblers.balanceOf(address(community)), 2);
    }

    /// @notice Test minting reserved gobblers fails if not enough have gobblers been minted.
    function testCantMintTooFastReserved() public {
        mintGobblerToAddress(users[0], 18);

        vm.expectRevert(ArtGobblers.ReserveImbalance.selector);
        gobblers.mintReservedGobblers(3);
    }

    /// @notice Test minting reserved gobblers fails one by one if not enough have gobblers been minted.
    function testCantMintTooFastReservedOneByOne() public {
        mintGobblerToAddress(users[0], 90);

        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);
        gobblers.mintReservedGobblers(1);

        vm.expectRevert(ArtGobblers.ReserveImbalance.selector);
        gobblers.mintReservedGobblers(1);
    }

    /*//////////////////////////////////////////////////////////////
                              PRICING TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test VRGDA behavior when selling at target rate.
    function testPricingBasic() public {
        // VRGDA targets this number of mints at given time.
        uint256 timeDelta = 120 days;
        // chosen such that gobblers.getTargetSaleTime(int256(numMint * 1e18))) ~ 120e18
        uint256 numMint = 877;
        vm.warp(block.timestamp + timeDelta);

        for (uint256 i = 0; i < numMint; ++i) {
            vm.startPrank(address(gobblers));
            uint256 price = gobblers.gobblerPrice();
            goo.mintForGobblers(users[0], price);
            vm.stopPrank();
            vm.prank(users[0]);
            gobblers.mintFromGoo(price);
        }

        uint256 targetPrice = uint256(gobblers.targetPrice());
        uint256 finalPrice = gobblers.gobblerPrice();

        // Equal within 3 percent since num mint is rounded from true decimal amount.
        assertRelApproxEq(finalPrice, targetPrice, 0.03e18);
    }

    /// @notice Pricing function should NOT revert when trying to price the last mintable gobbler.
    function testDoesNotRevertEarly() public view {
        // This is the last gobbler we expect to mint.
        int256 maxMintable = int256(gobblers.MAX_MINTABLE()) * 1e18;
        // This call should NOT revert, since we should have a target date for the last mintable gobbler.
        gobblers.getTargetSaleTime(maxMintable);
    }

    /// @notice Pricing function should revert when trying to price beyond the last mintable gobbler.
    function testDoesRevertWhenExpected() public {
        // One plus the max number of mintable gobblers.
        int256 maxMintablePlusOne = int256(gobblers.MAX_MINTABLE() + 1) * 1e18;
        // This call should revert, since there should be no target date beyond max mintable gobblers.
        vm.expectRevert("UNDEFINED");
        gobblers.getTargetSaleTime(maxMintablePlusOne);
    }

    /*//////////////////////////////////////////////////////////////
                                  URIS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test unminted URI is correct.
    function testUnmintedUri() public {
        hevm.expectRevert("NOT_MINTED");
        gobblers.tokenURI(1);
    }

    /// @notice Test that unrevealed URI is correct.
    function testUnrevealedUri() public {
        uint256 gobblerCost = gobblers.gobblerPrice();
        vm.prank(address(gobblers));
        goo.mintForGobblers(users[0], gobblerCost);
        vm.prank(users[0]);
        gobblers.mintFromGoo(type(uint256).max);
        // assert gobbler not revealed after mint
        assertTrue(stringEquals(gobblers.tokenURI(1), gobblers.UNREVEALED_URI()));
    }

    /// @notice Test that revealed URI is correct.
    function testRevealedUri() public {
        mintGobblerToAddress(users[0], 1);
        // unrevealed gobblers have 0 value attributes
        vm.warp(block.timestamp + 1 days);
        setRandomnessAndReveal(1, "seed");
        (, uint64 expectedIndex) = gobblers.getGobblerData(1);
        string memory expectedURI = string(abi.encodePacked(gobblers.BASE_URI(), uint256(expectedIndex).toString()));
        assertTrue(stringEquals(gobblers.tokenURI(1), expectedURI));
    }

    /*//////////////////////////////////////////////////////////////
                                 REVEALS
    //////////////////////////////////////////////////////////////*/

    function testDoesNotAllowRevealingZero() public {
        vm.warp(block.timestamp + 24 hours);
        vm.expectRevert(ArtGobblers.ZeroToBeRevealed.selector);
        gobblers.requestRandomSeed();
    }

    /// @notice Cannot request random seed before 24 hours have passed from initial mint.
    function testRevealDelayInitialMint() public {
        mintGobblerToAddress(users[0], 1);
        vm.expectRevert(ArtGobblers.RequestTooEarly.selector);
        gobblers.requestRandomSeed();
    }

    /// @notice Cannot reveal more gobblers than remaining to be revealed.
    function testCannotRevealMoreGobblersThanRemainingToBeRevealed() public {
        mintGobblerToAddress(users[0], 1);

        vm.warp(block.timestamp + 24 hours);

        bytes32 requestId = gobblers.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked("seed")));
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));

        mintGobblerToAddress(users[0], 2);

        vm.expectRevert(abi.encodeWithSelector(ArtGobblers.NotEnoughRemainingToBeRevealed.selector, 1));
        gobblers.revealGobblers(2);
    }

    /// @notice Cannot request random seed before 24 hours have passed from last reveal,
    function testRevealDelayRecurring() public {
        // Mint and reveal first gobbler
        mintGobblerToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);
        setRandomnessAndReveal(1, "seed");
        // Attempt reveal before 24 hours have passed
        mintGobblerToAddress(users[0], 1);
        vm.expectRevert(ArtGobblers.RequestTooEarly.selector);
        gobblers.requestRandomSeed();
    }

    /// @notice Test that seed can't be set without first revealing pending gobblers.
    function testCantSetRandomSeedWithoutRevealing() public {
        mintGobblerToAddress(users[0], 2);
        vm.warp(block.timestamp + 1 days);
        setRandomnessAndReveal(1, "seed");
        vm.warp(block.timestamp + 1 days);
        // should fail since there is one remaining gobbler to be revealed with seed
        vm.expectRevert(ArtGobblers.RevealsPending.selector);
        setRandomnessAndReveal(1, "seed");
    }

    /// @notice Test that revevals work as expected
    function testMultiReveal() public {
        mintGobblerToAddress(users[0], 100);
        // first 100 gobblers should be unrevealed
        for (uint256 i = 1; i <= 100; ++i) {
            assertEq(gobblers.tokenURI(i), gobblers.UNREVEALED_URI());
        }

        vm.warp(block.timestamp + 1 days); // can only reveal every 24 hours

        setRandomnessAndReveal(50, "seed");
        // first 50 gobblers should now be revealed
        for (uint256 i = 1; i <= 50; ++i) {
            assertTrue(!stringEquals(gobblers.tokenURI(i), gobblers.UNREVEALED_URI()));
        }
        // and next 50 should remain unrevealed
        for (uint256 i = 51; i <= 100; ++i) {
            assertTrue(stringEquals(gobblers.tokenURI(i), gobblers.UNREVEALED_URI()));
        }
    }

    function testCannotReuseSeedForReveal() public {
        // first mint and reveal.
        mintGobblerToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);
        setRandomnessAndReveal(1, "seed");
        // seed used for first reveal.
        (uint64 firstSeed,,,,) = gobblers.gobblerRevealsData();
        // second mint.
        mintGobblerToAddress(users[0], 1);
        vm.warp(block.timestamp + 1 days);
        gobblers.requestRandomSeed();
        // seed we want to use for second reveal.
        (uint64 secondSeed,,,,) = gobblers.gobblerRevealsData();
        // verify that we are trying to use the same seed.
        assertEq(firstSeed, secondSeed);
        // try to reveal with same seed, which should fail.
        vm.expectRevert(ArtGobblers.SeedPending.selector);
        gobblers.revealGobblers(1);
        assertTrue(true);
    }

    /*//////////////////////////////////////////////////////////////
                           LONG-RUNNING TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check that max supply is mintable
    function testLongRunningMintMaxFromGoo() public {
        uint256 maxMintableWithGoo = gobblers.MAX_MINTABLE();

        for (uint256 i = 0; i < maxMintableWithGoo; ++i) {
            vm.warp(block.timestamp + 1 days);
            uint256 cost = gobblers.gobblerPrice();
            vm.prank(address(gobblers));
            goo.mintForGobblers(users[0], cost);
            vm.prank(users[0]);
            gobblers.mintFromGoo(type(uint256).max);
        }
    }

    /// @notice Check that minting beyond max supply should revert.
    function testLongRunningMintMaxFromGooRevert() public {
        uint256 maxMintableWithGoo = gobblers.MAX_MINTABLE();

        for (uint256 i = 0; i < maxMintableWithGoo + 1; ++i) {
            vm.warp(block.timestamp + 1 days);

            if (i == maxMintableWithGoo) vm.expectRevert("UNDEFINED");
            uint256 cost = gobblers.gobblerPrice();

            vm.prank(address(gobblers));
            goo.mintForGobblers(users[0], cost);
            vm.prank(users[0]);

            if (i == maxMintableWithGoo) vm.expectRevert("UNDEFINED");
            gobblers.mintFromGoo(type(uint256).max);
        }
    }

    /// @notice Check that max reserved supplies are mintable.
    function testLongRunningMintMaxReserved() public {
        uint256 maxMintableWithGoo = gobblers.MAX_MINTABLE();

        for (uint256 i = 0; i < maxMintableWithGoo; ++i) {
            vm.warp(block.timestamp + 1 days);
            uint256 cost = gobblers.gobblerPrice();
            vm.prank(address(gobblers));
            goo.mintForGobblers(users[0], cost);
            vm.prank(users[0]);
            gobblers.mintFromGoo(type(uint256).max);
        }

        gobblers.mintReservedGobblers(gobblers.RESERVED_SUPPLY() / 2);
    }

    /// @notice Check that minting reserves beyond their max supply reverts.
    function testLongRunningMintMaxTeamRevert() public {
        uint256 maxMintableWithGoo = gobblers.MAX_MINTABLE();

        for (uint256 i = 0; i < maxMintableWithGoo; ++i) {
            vm.warp(block.timestamp + 1 days);
            uint256 cost = gobblers.gobblerPrice();
            vm.prank(address(gobblers));
            goo.mintForGobblers(users[0], cost);
            vm.prank(users[0]);
            gobblers.mintFromGoo(type(uint256).max);
        }

        gobblers.mintReservedGobblers(gobblers.RESERVED_SUPPLY() / 2);

        vm.expectRevert(ArtGobblers.ReserveImbalance.selector);
        gobblers.mintReservedGobblers(1);
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
            gobblers.mintFromGoo(type(uint256).max);

            assertEq(gobblers.balanceOf(addr), gobblersOwnedBefore + 1);
        }
    }

    /// @notice Call back vrf with randomness and reveal gobblers.
    function setRandomnessAndReveal(uint256 numReveal, string memory seed) internal {
        bytes32 requestId = gobblers.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked(seed)));
        // call back from coordinator
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));
        gobblers.revealGobblers(numReveal);
    }

    /// @notice Check for string equality.
    function stringEquals(string memory s1, string memory s2) internal pure returns (bool) {
        return keccak256(abi.encodePacked(s1)) == keccak256(abi.encodePacked(s2));
    }
}
