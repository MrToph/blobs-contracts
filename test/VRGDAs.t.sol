// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";
import {Blobs} from "../src/Blobs.sol";
import {Goo} from "../src/Goo.sol";
import {LinkToken} from "./utils/mocks/LinkToken.sol";
import {VRFCoordinatorMock} from "chainlink/v0.8/mocks/VRFCoordinatorMock.sol";
import {RandProvider} from "../src/utils/rand/RandProvider.sol";
import {ChainlinkV1RandProvider} from "../src/utils/rand/ChainlinkV1RandProvider.sol";
import {toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

contract VRGDAsTest is DSTestPlus {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    uint256 constant ONE_THOUSAND_YEARS = 356 days * 1000;

    Utilities internal utils;
    address payable[] internal users;

    Blobs private blobs;
    VRFCoordinatorMock private vrfCoordinator;
    LinkToken private linkToken;

    Goo goo;
    RandProvider randProvider;

    bytes32 private keyHash;
    uint256 private fee;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);
        linkToken = new LinkToken();
        vrfCoordinator = new VRFCoordinatorMock(address(linkToken));

        //blobs contract will be deployed after 2 contract deploys
        address gobblerAddress = utils.predictContractAddress(address(this), 2);

        randProvider = new ChainlinkV1RandProvider(
            Blobs(gobblerAddress),
            address(vrfCoordinator),
            address(linkToken),
            keyHash,
            fee
        );

        goo = new Goo(gobblerAddress, address(0xDEAD));

        blobs = new Blobs(
            "root",
            block.timestamp,
            goo,
            address(0xBEEF),
            address(0xBEEF),
            randProvider,
            "base",
            ""
        );
    }

    // function testFindGobblerOverflowPoint() public view {
    //     uint256 sold;
    //     while (true) {
    //         blobs.getPrice(0 days, sold++);
    //     }
    // }

    function testNoOverflowForMostBlobs(uint256 timeSinceStart, uint256 sold) public {
        blobs.getVRGDAPrice(toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_THOUSAND_YEARS)), bound(sold, 0, 1730));
    }

    function testNoOverflowForAllBlobs(uint256 timeSinceStart, uint256 sold) public {
        blobs.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 3870 days, ONE_THOUSAND_YEARS)),
            bound(sold, 0, blobs.MAX_MINTABLE() - 1)
        );
    }

    function testFailOverflowForBeyondLimitBlobs(uint256 timeSinceStart, uint256 sold) public {
        // Blobs calls getVRGDAPrice(., numMintedFromGoo) where numMintedFromGoo < MAX_MINTABLE()
        blobs.getVRGDAPrice(
            toDaysWadUnsafe(bound(timeSinceStart, 0 days, ONE_THOUSAND_YEARS)),
            bound(sold, blobs.MAX_MINTABLE(), type(uint128).max)
        );
    }

    function testGobblerPriceStrictlyIncreasesForMostBlobs() public {
        uint256 sold;
        uint256 previousPrice;

        while (sold <= 1730) {
            uint256 price = blobs.getVRGDAPrice(0 days, sold++);
            assertGt(price, previousPrice);
            previousPrice = price;
        }
    }
}
