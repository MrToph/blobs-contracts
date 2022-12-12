// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;


import {DeployBase} from "./DeployBase.s.sol";

contract DeployLocal is DeployBase {
    address public constant teamColdWallet = 0x206FaEC0008DE8Fc5aFCFc16002334c30Bb2F1f0;

    address public constant root = 0x06b8ed08Fb5042b8797f620df1B5998eB0e244F0;

    uint256 public constant mintStart = 1656369768;

    string public constant blobBaseUri = "https://nfts.artgobblers.com/api/gobblers/";
    string public constant blobUnrevealedUri = "https://nfts.artgobblers.com/api/gobblers/unrevealed";

    constructor(address gobblersAddress)
        // Team cold wallet:
        DeployBase(
            gobblersAddress,
            teamColdWallet,
            // Merkle root:
            keccak256(abi.encodePacked(root)),
            // Mint start:
            mintStart,
            // VRF coordinator:
            address(0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B),
            // LINK token:
            address(0x01BE23585060835E02B77ef475b0Cc51aA1e0709),
            // Chainlink hash:
            0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311,
            // Chainlink fee:
            0.1e18,
            // Blob base URI:
            blobBaseUri,
            // Blob unrevealed URI:
            blobUnrevealedUri
        )
    {}
}
