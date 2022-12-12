// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {NounsDAOExecutor} from "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOExecutor.sol";
import {NounsDAOProxyV2} from "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOProxyV2.sol";
import {NounsDAOLogicV2} from "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOLogicV2.sol";
import "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOInterfaces.sol";

import {LibRLP} from "../../test/utils/LibRLP.sol";

import {RandProvider} from "../../src/utils/rand/RandProvider.sol";
import {ChainlinkV1RandProvider} from "../../src/utils/rand/ChainlinkV1RandProvider.sol";

import {Goo} from "art-gobblers/Goo.sol";
import {ArtGobblers} from "art-gobblers/ArtGobblers.sol";

import {Blobs} from "../../src/Blobs.sol";
import {GobblersTreasury} from "../../src/GobblersTreasury.sol";

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
    RandProvider public randProvider;
    Blobs public blobs;
    ArtGobblers public gobblers;
    Goo public goo;
    GobblersTreasury public gobblersTreasury;

    // Governance
    uint256 constant executionDelaySeconds = 3 days; // earliest eta a successful execution can be queued in timelock.queueTransaction. I guess this is an additional safety measure for the vetoer to call veto. time for everyone to sign an msig
    // Nouns uses delay of 14400 = 2 days @ 12 seconds per block
    uint256 constant votingDelayBlocks = 2 days / 12; // # blocks after proposing when users can start voting
    // Nouns uses delay of 36000 = 5 days @ 12 seconds per block
    uint256 constant votingPeriodBlocks = 5 days / 12; // # blocks users can vote on proposals
    NounsDAOExecutor public timelock;
    NounsDAOLogicV2 public proxy;

    constructor(
        address _gobblers,
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
        gobblers = ArtGobblers(_gobblers);
        goo = ArtGobblers(_gobblers).goo();
    }

    function run() external {
        vm.startBroadcast();

        // Precomputed contract addresses, based on contract deploy nonces.
        // tx.origin is the address who will actually broadcast the contract creations below.
        address proxyGovernanceAddress = LibRLP.computeAddress(tx.origin, vm.getNonce(tx.origin) + 2);
        address blobAddress = LibRLP.computeAddress(tx.origin, vm.getNonce(tx.origin) + 5);

        // Deploy Governance
        timelock = new NounsDAOExecutor({admin_: proxyGovernanceAddress, delay_: executionDelaySeconds});
        NounsDAOStorageV2.DynamicQuorumParams memory dynamicQuorumParams = NounsDAOStorageV2.DynamicQuorumParams({
            minQuorumVotesBPS: 0.1000e4,
            maxQuorumVotesBPS: 0.1500e4,
            quorumCoefficient: 1e6
        });

        // no need to initialize the NounsGovernance implementation because `admin` is 0 and it checks `msg.sender === admin` in `initialize`
        NounsDAOLogicV2 implementation = new NounsDAOLogicV2();

        // its constructor already calls implemenation.initialize(args)
        NounsDAOProxyV2 p = new NounsDAOProxyV2({
            timelock_: address(timelock),
            nouns_: blobAddress,
            vetoer_: address(teamColdWallet),
            admin_: address(teamColdWallet), // can set voting delays, voting periods, thresholds
            implementation_: address(implementation),
            votingPeriod_: votingPeriodBlocks,
            votingDelay_: votingDelayBlocks,
            proposalThresholdBPS_: 25, // proposalThresholdBPS * totalSupply / 1e4 required of msg.sender to _propose_
            dynamicQuorumParams_: dynamicQuorumParams
        });
        proxy = NounsDAOLogicV2(payable(p)); // treat the proxy as a NounsDAOLogicV2


        gobblersTreasury = new GobblersTreasury(address(timelock), address(gobblers));

        // Deploy team and community reserves, owned by cold wallet.
        randProvider = new ChainlinkV1RandProvider(
            Blobs(blobAddress),
            vrfCoordinator,
            linkToken,
            chainlinkKeyHash,
            chainlinkFee
        );

        // Deploy blobs contract,
        blobs = new Blobs(
            merkleRoot,
            mintStart,
            goo,
            teamColdWallet,
            address(gobblersTreasury),
            randProvider,
            blobBaseUri,
            blobUnrevealedUri
        );

        vm.stopBroadcast();
    }
}
