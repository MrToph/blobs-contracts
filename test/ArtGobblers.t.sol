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
        uint256 numMint = 876;

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
                           LEGENDARY GOBBLERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that attempting to mint before start time reverts.
    function testLegendaryGobblerMintBeforeStart() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ArtGobblers.LegendaryAuctionNotStarted.selector, gobblers.LEGENDARY_AUCTION_INTERVAL()
            )
        );
        vm.prank(users[0]);
        gobblers.mintLegendaryGobbler(ids);
    }

    /// @notice Test that Legendary Gobbler initial price is what we expect.
    function testLegendaryGobblerTargetPrice() public {
        // Start of initial auction after initial interval is minted.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL());
        uint256 cost = gobblers.legendaryGobblerPrice();
        // Initial auction should start at a cost of 69.
        assertEq(cost, 69);
    }

    /// @notice Test that auction ends at a price of 0.
    function testLegendaryGobblerFinalPrice() public {
        // Mint 2 full intervals.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL() * 2);
        uint256 cost = gobblers.legendaryGobblerPrice();
        // Auction price should be 0 after full interval decay.
        assertEq(cost, 0);
    }

    /// @notice Test that auction ends at a price of 0 even after the interval.
    function testLegendaryGobblerPastFinalPrice() public {
        // Mint 3 full intervals.
        vm.warp(block.timestamp + 600 days);
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL() * 3);
        uint256 cost = gobblers.legendaryGobblerPrice();
        // Auction price should be 0 after full interval decay.
        assertEq(cost, 0);
    }

    /// @notice Test that mid price happens when we expect.
    function testLegendaryGobblerMidPrice() public {
        // Mint first interval and half of second interval.
        mintGobblerToAddress(users[0], FixedPointMathLib.unsafeDivUp(gobblers.LEGENDARY_AUCTION_INTERVAL() * 3, 2));
        uint256 cost = gobblers.legendaryGobblerPrice();
        // Auction price should be cut by half mid way through auction.
        assertEq(cost, 35);
    }

    /// @notice Test that target price does't fall below what we expect.
    function testLegendaryGobblerMinStartPrice() public {
        // Mint two full intervals, such that price of first auction goes to zero.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL() * 2);
        // Empty id list.
        uint256[] memory _ids;
        // Mint first auction at zero cost.
        gobblers.mintLegendaryGobbler(_ids);
        // Start cost of next auction, which should equal 69.
        uint256 startCost = gobblers.legendaryGobblerPrice();
        assertEq(startCost, 69);
    }

    /// @notice Test that Legendary Gobblers can be minted.
    function testMintLegendaryGobbler() public {
        uint256 startTime = block.timestamp + 30 days;
        vm.warp(startTime);
        // Mint full interval to kick off first auction.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL());
        uint256 cost = gobblers.legendaryGobblerPrice();
        assertEq(cost, 69);
        setRandomnessAndReveal(cost, "seed");
        for (uint256 curId = 1; curId <= cost; curId++) {
            ids.push(curId);
            assertEq(gobblers.ownerOf(curId), users[0]);
        }

        vm.prank(users[0]);
        uint256 mintedLegendaryId = gobblers.mintLegendaryGobbler(ids);

        // Legendary is owned by user.
        assertEq(gobblers.ownerOf(mintedLegendaryId), users[0]);

        for (uint256 i = 0; i < ids.length; ++i) {
            hevm.expectRevert("NOT_MINTED");
            gobblers.ownerOf(ids[i]);
        }
    }

    /// @notice Test that owned counts are computed properly when minting a legendary
    function testLegendaryMintBalance() public {
        uint256 startTime = block.timestamp + 30 days;
        vm.warp(startTime);
        // Mint full interval to kick off first auction.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL());
        uint256 cost = gobblers.legendaryGobblerPrice();
        assertEq(cost, 69);
        setRandomnessAndReveal(cost, "seed");
        for (uint256 curId = 1; curId <= cost; curId++) {
            ids.push(curId);
        }

        uint256 initialBalance = gobblers.balanceOf(users[0]);
        vm.prank(users[0]);
        gobblers.mintLegendaryGobbler(ids);

        uint256 finalBalance = gobblers.balanceOf(users[0]);

        // Check balance is computed correctly
        assertEq(finalBalance, initialBalance - cost + 1);
    }

    /// @notice Test that Legendary Gobblers can be minted at 0 cost.
    function testMintFreeLegendaryGobbler() public {
        uint256 startTime = block.timestamp + 30 days;
        vm.warp(startTime);

        // Mint 2 full intervals to send price to zero.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL() * 2);

        uint256 cost = gobblers.legendaryGobblerPrice();
        assertEq(cost, 0);

        vm.prank(users[0]);
        uint256 mintedLegendaryId = gobblers.mintLegendaryGobbler(ids);

        assertEq(gobblers.ownerOf(mintedLegendaryId), users[0]);
    }

    /// @notice Test that Legendary Gobblers can be minted at 0 cost.
    function testMintFreeLegendaryGobblerPastInterval() public {
        uint256 startTime = block.timestamp + 30 days;
        vm.warp(startTime);

        // Mint 3 full intervals to send price to zero.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL() * 3);

        uint256 cost = gobblers.legendaryGobblerPrice();
        assertEq(cost, 0);

        vm.prank(users[0]);
        uint256 mintedLegendaryId = gobblers.mintLegendaryGobbler(ids);

        assertEq(gobblers.ownerOf(mintedLegendaryId), users[0]);
    }

    /// @notice Test that legendary gobblers can't be minted with insufficient payment.
    function testMintLegendaryGobblerWithInsufficientCost() public {
        uint256 startTime = block.timestamp + 30 days;
        vm.warp(startTime);
        // Mint full interval to kick off first auction.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL());
        uint256 cost = gobblers.legendaryGobblerPrice();
        assertEq(cost, 69);
        setRandomnessAndReveal(cost, "seed");
        for (uint256 curId = 1; curId <= cost; curId++) {
            ids.push(curId);
            assertEq(gobblers.ownerOf(curId), users[0]);
        }

        //remove one id such that payment is insufficient
        ids.pop();

        vm.prank(users[0]);
        vm.expectRevert(abi.encodeWithSelector(ArtGobblers.InsufficientGobblerAmount.selector, cost));
        gobblers.mintLegendaryGobbler(ids);
    }

    /// @notice Test that legendary gobblers can be minted with slippage.
    function testMintLegendaryGobblerWithSlippage() public {
        uint256 startTime = block.timestamp + 30 days;
        vm.warp(startTime);
        // Mint full interval to kick off first auction.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL());
        uint256 cost = gobblers.legendaryGobblerPrice();
        assertEq(cost, 69);
        setRandomnessAndReveal(cost, "seed");
        //add more ids than necessary
        for (uint256 curId = 1; curId <= cost + 10; curId++) {
            ids.push(curId);
            assertEq(gobblers.ownerOf(curId), users[0]);
        }

        vm.prank(users[0]);
        gobblers.mintLegendaryGobbler(ids);

        //check full cost was burned
        for (uint256 curId = 1; curId <= cost; curId++) {
            hevm.expectRevert("NOT_MINTED");
            gobblers.ownerOf(curId);
        }
        //check extra tokens were not burned
        for (uint256 curId = cost + 1; curId <= cost + 10; curId++) {
            assertEq(gobblers.ownerOf(curId), users[0]);
        }
    }

    /// @notice Test that legendary gobblers can't be minted if the user doesn't own one of the ids.
    function testMintLegendaryGobblerWithUnownedId() public {
        uint256 startTime = block.timestamp + 30 days;
        vm.warp(startTime);
        // Mint full interval to kick off first auction.
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL());
        uint256 cost = gobblers.legendaryGobblerPrice();
        assertEq(cost, 69);
        setRandomnessAndReveal(cost, "seed");
        for (uint256 curId = 1; curId <= cost; curId++) {
            ids.push(curId);
            assertEq(gobblers.ownerOf(curId), users[0]);
        }

        ids.pop();
        ids.push(999);

        vm.prank(users[0]);
        vm.expectRevert("WRONG_FROM");
        gobblers.mintLegendaryGobbler(ids);
    }

    /// @notice Test that legendary gobblers have expected ids.
    function testMintLegendaryGobblersExpectedIds() public {
        // We expect the first legendary to have this id.
        uint256 nextMintLegendaryId = 9991;
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL());
        for (int256 i = 0; i < 10; ++i) {
            vm.warp(block.timestamp + 400 days);

            mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL());
            uint256 justMintedLegendaryId = gobblers.mintLegendaryGobbler(ids);
            //assert that legendaries have the expected ids
            assertEq(nextMintLegendaryId, justMintedLegendaryId);
            nextMintLegendaryId++;
        }

        // Minting any more should fail.
        vm.expectRevert(ArtGobblers.NoRemainingLegendaryGobblers.selector);
        gobblers.mintLegendaryGobbler(ids);
    }

    /// @notice Test that Legendary Gobblers can't be burned to mint another legendary.
    function testCannotMintLegendaryWithLegendary() public {
        vm.warp(block.timestamp + 30 days);

        mintNextLegendary(users[0]);
        uint256 mintedLegendaryId = gobblers.FIRST_LEGENDARY_GOBBLER_ID();
        //First legendary to be minted should be 9991
        assertEq(mintedLegendaryId, 9991);
        uint256 cost = gobblers.legendaryGobblerPrice();

        // Starting price should be 69.
        assertEq(cost, 69);
        setRandomnessAndReveal(cost, "seed");
        for (uint256 i = 1; i <= cost; ++i) {
            ids.push(i);
        }

        ids[0] = mintedLegendaryId; // Try to pass in the legendary we just minted as well.
        vm.prank(users[0]);
        vm.expectRevert(abi.encodeWithSelector(ArtGobblers.CannotBurnLegendary.selector, mintedLegendaryId));
        gobblers.mintLegendaryGobbler(ids);
    }

    function testCanReuseSacrificedGobblers() public {
        address user = users[0];

        // setup legendary mint
        uint256 startTime = block.timestamp + 30 days;
        vm.warp(startTime);
        mintGobblerToAddress(user, gobblers.LEGENDARY_AUCTION_INTERVAL());
        uint256 cost = gobblers.legendaryGobblerPrice();
        assertEq(cost, 69);
        setRandomnessAndReveal(cost, "seed");

        for (uint256 curId = 1; curId <= cost; curId++) {
            ids.push(curId);
            assertEq(gobblers.ownerOf(curId), users[0]);
        }

        // do token approvals for vulnerability exploit
        vm.startPrank(user);
        for (uint256 i = 0; i < ids.length; i++) {
            gobblers.approve(user, ids[i]);
        }
        vm.stopPrank();

        // mint legendary
        vm.prank(user);
        uint256 mintedLegendaryId = gobblers.mintLegendaryGobbler(ids);

        // confirm user owns legendary
        assertEq(gobblers.ownerOf(mintedLegendaryId), user);

        // show that contract initially thinks tokens are burnt
        for (uint256 i = 0; i < ids.length; i++) {
            vm.expectRevert("NOT_MINTED");
            gobblers.ownerOf(ids[i]);
        }

        // should not be able to revive burned gobblers
        vm.startPrank(user);
        for (uint256 i = 0; i < ids.length; i++) {
            vm.expectRevert("NOT_AUTHORIZED");
            gobblers.transferFrom(address(0), user, ids[i]);
        }
        vm.stopPrank();
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

    /// @notice Test that legendary gobbler URI is correct.
    function testMintedLegendaryURI() public {
        //mint legendary for free
        mintGobblerToAddress(users[0], gobblers.LEGENDARY_AUCTION_INTERVAL() * 2);
        uint256 currentLegendaryId = gobblers.mintLegendaryGobbler(ids);

        //expected URI should not be shuffled
        string memory expectedURI =
            string(abi.encodePacked(gobblers.BASE_URI(), uint256(currentLegendaryId).toString()));
        string memory actualURI = gobblers.tokenURI(currentLegendaryId);
        assertTrue(stringEquals(actualURI, expectedURI));
    }

    /// @notice Test that un-minted legendary gobbler URI is correct.
    function testUnmintedLegendaryUri() public {
        uint256 currentLegendaryId = gobblers.FIRST_LEGENDARY_GOBBLER_ID();

        hevm.expectRevert("NOT_MINTED");
        gobblers.tokenURI(currentLegendaryId);

        hevm.expectRevert("NOT_MINTED");
        gobblers.tokenURI(currentLegendaryId + 1);
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

    function mintNextLegendary(address addr) internal {
        uint256[] memory id;
        mintGobblerToAddress(addr, gobblers.LEGENDARY_AUCTION_INTERVAL() * 2);
        vm.prank(addr);
        gobblers.mintLegendaryGobbler(id);
    }
}
