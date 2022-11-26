// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {LibRLP} from "../../test/utils/LibRLP.sol";

import {BlobReserve} from "../../src/utils/BlobReserve.sol";
import {RandProvider} from "../../src/utils/rand/RandProvider.sol";
import {ChainlinkV1RandProvider} from "../../src/utils/rand/ChainlinkV1RandProvider.sol";

import {Goo} from "../../src/Goo.sol";
import {Blobs} from "../../src/Blobs.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    address private immutable teamColdWallet;
    bytes32 private immutable merkleRoot;
    uint256 private immutable mintStart;
    address private immutable vrfCoordinator;
    address private immutable linkToken;
    bytes32 private immutable chainlinkKeyHash;
    uint256 private immutable chainlinkFee;
    string private blobBaseUri;
    string private blobUnrevealedUri;

    // Deploy addresses.
    BlobReserve public teamReserve;
    BlobReserve public communityReserve;
    Goo public goo;
    RandProvider public randProvider;
    Blobs public blobs;

    constructor(
        address _teamColdWallet,
        bytes32 _merkleRoot,
        uint256 _mintStart,
        address _vrfCoordinator,
        address _linkToken,
        bytes32 _chainlinkKeyHash,
        uint256 _chainlinkFee,
        string memory _blobBaseUri,
        string memory _blobUnrevealedUri
    ) {
        teamColdWallet = _teamColdWallet;
        merkleRoot = _merkleRoot;
        mintStart = _mintStart;
        vrfCoordinator = _vrfCoordinator;
        linkToken = _linkToken;
        chainlinkKeyHash = _chainlinkKeyHash;
        chainlinkFee = _chainlinkFee;
        blobBaseUri = _blobBaseUri;
        blobUnrevealedUri = _blobUnrevealedUri;
    }

    function run() external {
        vm.startBroadcast();

        // Precomputed contract addresses, based on contract deploy nonces.
        // tx.origin is the address who will actually broadcast the contract creations below.
        address blobAddress = LibRLP.computeAddress(tx.origin, vm.getNonce(tx.origin) + 3);

        // Deploy team and community reserves, owned by cold wallet.
        teamReserve = new BlobReserve(Blobs(blobAddress), teamColdWallet);
        communityReserve = new BlobReserve(Blobs(blobAddress), teamColdWallet);
        randProvider = new ChainlinkV1RandProvider(
            Blobs(blobAddress),
            vrfCoordinator,
            linkToken,
            chainlinkKeyHash,
            chainlinkFee
        );

        // Get goo contract.
        goo = Goo(address(0xDEAD)); // TODO: get deployed Goo here

        // Deploy blobs contract,
        blobs = new Blobs(
            merkleRoot,
            mintStart,
            goo,
            address(teamReserve),
            address(communityReserve),
            randProvider,
            blobBaseUri,
            blobUnrevealedUri
        );

        vm.stopBroadcast();
    }
}
