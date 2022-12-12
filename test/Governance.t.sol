// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Test, stdError} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Utilities} from "./utils/Utilities.sol";
import {Blobs, FixedPointMathLib} from "../src/Blobs.sol";
import {Goo} from "art-gobblers/Goo.sol";
import {BlobReserve} from "../src/utils/BlobReserve.sol";
import {RandProvider} from "../src/utils/rand/RandProvider.sol";
import {ChainlinkV1RandProvider} from "../src/utils/rand/ChainlinkV1RandProvider.sol";
import {LinkToken} from "./utils/mocks/LinkToken.sol";
import {VRFCoordinatorMock} from "chainlink/v0.8/mocks/VRFCoordinatorMock.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {MockERC1155} from "solmate/test/utils/mocks/MockERC1155.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {fromDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {NounsDAOExecutor} from "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOExecutor.sol";
import {NounsDAOProxyV2} from "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOProxyV2.sol";
import {NounsDAOLogicV2} from "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOLogicV2.sol";
import "nouns-monorepo/packages/nouns-contracts/contracts/governance/NounsDAOInterfaces.sol";

enum Support {
    Against,
    For,
    Abstain
}

/// @notice Unit test for Art Blob Contract.
contract GovernanceTest is Test {
    using LibString for uint256;

    Utilities internal utils;
    address payable[] internal users;

    Blobs internal blobs;
    VRFCoordinatorMock internal vrfCoordinator;
    LinkToken internal linkToken;
    Goo internal goo;
    address internal constant foundersMsig = address(0x13371338);
    RandProvider internal randProvider;

    // for VRF
    bytes32 private keyHash;
    uint256 private fee;

    uint256[] ids;

    // Governance
    uint256 constant executionDelaySeconds = 3 days; // earliest eta a successful execution can be queued in timelock.queueTransaction. I guess this is an additional safety measure for the vetoer to call veto. time for everyone to sign an msig
    // Nouns uses delay of 14400 = 2 days @ 12 seconds per block
    uint256 constant votingDelayBlocks = 2 days / 12; // # blocks after proposing when users can start voting
    // Nouns uses delay of 36000 = 5 days @ 12 seconds per block
    uint256 constant votingPeriodBlocks = 5 days / 12; // # blocks users can vote on proposals
    NounsDAOExecutor private timelock;
    NounsDAOLogicV2 private proxy;

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);
        linkToken = new LinkToken();
        vrfCoordinator = new VRFCoordinatorMock(address(linkToken));

        //blobs contract will be deployed after 4 contract deploys
        address blobAddress = utils.predictContractAddress(address(this), 2);

        randProvider = new ChainlinkV1RandProvider(
            Blobs(blobAddress),
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
            // team blobs directly go to team, community blobs too and are to be distributed
            address(foundersMsig),
            address(foundersMsig),
            randProvider,
            "base",
            ""
        );

        _deployGovernance();

        // users approve contract
        for (uint256 i = 0; i < users.length; ++i) {
            vm.prank(users[i]);
            goo.approve(address(blobs), type(uint256).max);
        }

        // send some goo to timelock
        vm.prank(address(blobs));
        goo.mintForGobblers(address(timelock), 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                               MINT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test that you can mint from mintlist successfully.
    function testProposalSuccess() public {
        _mintBlobToAddress(users[0], 2);
        _mintBlobToAddress(users[1], 8);
        assertEq(blobs.totalSupply(), 10);
        vm.roll(block.number + 1); // snapshot votes

        assertEq(blobs.balanceOf(users[0]), 2);
        assertEq(blobs.getPriorVotes(users[0], block.number - 1), 2);

        vm.startPrank(users[0]);
        // 1. Propose
        (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas,
            string memory description
        ) = _createProposal({
            target: address(goo),
            value: 0,
            signature: "transfer(address,uint256)",
            data: abi.encode(address(users[2]), 1e18),
            description: "Goo funding proposal #1"
        });
        uint256 proposalId = proxy.propose(targets, values, signatures, calldatas, description);
        vm.roll(block.number + votingDelayBlocks + 1); // skip voting delay + 1. +1 because of bug in NounsDAOLogicV2.state

        // 2. Cast vote
        // need to be >= quorumVotes(proposalId) which is defined as dynamicQuorumVotes(proposal.againstVotes, proposal.totalSupply):
        // The more against-votes there are for a proposal, the higher the required quorum is.
        console.log("quorum votes required %s", proxy.quorumVotes(proposalId));
        proxy.castVote(proposalId, uint8(Support.For));

        // 3. Queue proposal to timelock
        vm.roll(block.number + votingPeriodBlocks); // skip voting period
        proxy.queue(proposalId);
        NounsDAOStorageV1Adjusted.ProposalState state = proxy.state(proposalId);
        console.log("proposal state %s", uint256(state));

        // 4. Execute proposal
        // skip Timelock's execution delay
        vm.warp(block.timestamp + executionDelaySeconds);
        assertEq(goo.balanceOf(address(users[2])), 0);
        proxy.execute(proposalId);
        assertEq(goo.balanceOf(address(users[2])), 1e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/
    function _createProposal(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        string memory description
    )
        internal
        pure
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas,
            string memory descript
        )
    {
        targets = new address[](1);
        values = new uint256[](1);
        signatures = new string[](1);
        calldatas = new bytes[](1);
        targets[0] = target;
        values[0] = value;
        signatures[0] = signature;
        calldatas[0] = data;
        descript = description;
    }

    /// @notice Mint a number of blobs to the given address
    function _mintBlobToAddress(address addr, uint256 num) internal {
        for (uint256 i = 0; i < num; ++i) {
            vm.startPrank(address(blobs));
            goo.mintForGobblers(addr, blobs.blobPrice());
            vm.stopPrank();

            uint256 blobsOwnedBefore = blobs.balanceOf(addr);

            vm.prank(addr);
            // note: transfers goo from caller to Blobs.team
            blobs.mintFromGoo(type(uint256).max);

            assertEq(blobs.balanceOf(addr), blobsOwnedBefore + 1);
        }
    }

    function _deployGovernance() internal {
        timelock = new NounsDAOExecutor({admin_: address(foundersMsig), delay_: executionDelaySeconds});

        // https://etherscan.io/address/0x6f3e6272a167e8accb32072d08e0957f9c79223d#readProxyContract
        // 1000,1500,1_000_000
        NounsDAOStorageV2.DynamicQuorumParams memory dynamicQuorumParams = NounsDAOStorageV2.DynamicQuorumParams({
            minQuorumVotesBPS: 0.1000e4,
            maxQuorumVotesBPS: 0.1500e4,
            quorumCoefficient: 1e6
        });

        NounsDAOLogicV2 implementation = new NounsDAOLogicV2();

        // its constructor already calls implemenation.initialize(args)
        NounsDAOProxyV2 p = new NounsDAOProxyV2({
            timelock_: address(timelock),
            nouns_: address(blobs),
            vetoer_: address(foundersMsig),
            admin_: address(foundersMsig), // can set voting delays, voting periods, thresholds
            implementation_: address(implementation),
            votingPeriod_: votingPeriodBlocks,
            votingDelay_: votingDelayBlocks,
            proposalThresholdBPS_: 25, // proposalThresholdBPS * totalSupply / 1e4 required of msg.sender to _propose_
            dynamicQuorumParams_: dynamicQuorumParams
        });

        proxy = NounsDAOLogicV2(payable(p)); // treat the proxy as a NounsDAOLogicV2

        // change timelock's admin from founders' msig to governance contract
        string memory signature = "setPendingAdmin(address)"; // signature must be provided in string format as it's hashed in executeTransaction
        vm.startPrank(address(foundersMsig));
        uint256 eta = block.timestamp + executionDelaySeconds;
        timelock.queueTransaction({
            target: address(timelock),
            value: 0,
            signature: signature,
            data: abi.encode(address(proxy)),
            eta: eta
        });
        vm.warp(eta);
        timelock.executeTransaction({
            target: address(timelock),
            value: 0,
            signature: signature,
            data: abi.encode(address(proxy)),
            eta: eta
        });
        vm.stopPrank();

        vm.prank(address(proxy));
        timelock.acceptAdmin();
    }
}
