// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {DeployBase} from "./DeployBase.s.sol";

contract DeployGoerli is DeployBase {
    // https://goerli.etherscan.io/address/0x60bb1e2AA1c9ACAfB4d34F71585D7e959f387769#code
    address public constant gobblersAddress = 0x60bb1e2AA1c9ACAfB4d34F71585D7e959f387769;
    address public constant teamColdWallet = 0x206FaEC0008DE8Fc5aFCFc16002334c30Bb2F1f0;

    address public constant root = 0x06b8ed08Fb5042b8797f620df1B5998eB0e244F0;

    uint256 public constant mintStart = 1663809768;

    string public constant blobBaseUri = "https://nfts.artgobblers.com/api/gobblers/";
    string public constant blobUnrevealedUri = "https://nfts.artgobblers.com/api/gobblers/unrevealed";

    constructor()
        // Team cold wallet:
        DeployBase(
            gobblersAddress,
            teamColdWallet,
            // Merkle root:
            keccak256(abi.encodePacked(root)),
            // Mint start:
            mintStart,
            // VRF coordinator:
            address(0x2bce784e69d2Ff36c71edcB9F88358dB0DfB55b4),
            // LINK token:
            address(0x326C977E6efc84E512bB9C30f76E30c160eD06FB),
            // Chainlink hash:
            0x0476f9a745b61ea5c0ab224d3a6e4c99f0b02fce4da01143a4f70aa80ae76e8a,
            // Chainlink fee:
            0.1e18,
            // Blob base URI:
            blobBaseUri,
            // Blob unrevealed URI:
            blobUnrevealedUri
        )
    {}
}
