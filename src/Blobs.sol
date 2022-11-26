// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * Base: https://github.com/artgobblers/art-gobblers/tree/a337353df07193225aad40e8d6659bd67b0abb20
 * Modifications:
 * - removed anything related to goo balances, adding / removing goo
 * - removed legendary NFTs
 * - removed anything related to gobbling art
 */
import {Owned} from "solmate/auth/Owned.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {MerkleProofLib} from "solmate/utils/MerkleProofLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC1155, ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {toWadUnsafe, toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {LogisticVRGDA} from "VRGDAs/LogisticVRGDA.sol";

import {RandProvider} from "./utils/rand/RandProvider.sol";
import {ERC721Checkpointable} from "./utils/token/ERC721Checkpointable.sol";

import {Goo} from "./Goo.sol";

/// @title Blobs NFT
/// @notice An experimental decentralized art companion project to ArtBlobs
contract Blobs is ERC721Checkpointable, LogisticVRGDA, Owned, ERC1155TokenReceiver {
    using LibString for uint256;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the Goo ERC20 token contract.
    Goo public immutable goo;

    /// @notice The address which receives blobs reserved for the team.
    address public immutable team;

    /// @notice The address which receives blobs reserved for the community.
    address public immutable community;

    /// @notice The address of a randomness provider. This provider will initially be
    /// a wrapper around Chainlink VRF v1, but can be changed in case it is fully sunset.
    RandProvider public randProvider;

    /*//////////////////////////////////////////////////////////////
                            SUPPLY CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum number of mintable blobs.
    uint256 public constant MAX_SUPPLY = 10000;

    /// @notice Maximum amount of blobs mintable via mintlist.
    uint256 public constant MINTLIST_SUPPLY = 2000;

    /// @notice Maximum amount of blobs split between the reserves.
    /// @dev Set to comprise 20% of the sum of goo mintable blobs + reserved blobs.
    uint256 public constant RESERVED_SUPPLY = (MAX_SUPPLY - MINTLIST_SUPPLY) / 5;

    /// @notice Maximum amount of blobs that can be minted via VRGDA.
    // prettier-ignore
    uint256 public constant MAX_MINTABLE = MAX_SUPPLY - MINTLIST_SUPPLY - RESERVED_SUPPLY;

    /*//////////////////////////////////////////////////////////////
                           METADATA CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice URI for blobs that have yet to be revealed.
    string public UNREVEALED_URI;

    /// @notice Base URI for minted blobs.
    string public BASE_URI;

    /*//////////////////////////////////////////////////////////////
                             MINTLIST STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Merkle root of mint mintlist.
    bytes32 public immutable merkleRoot;

    /// @notice Mapping to keep track of which addresses have claimed from mintlist.
    mapping(address => bool) public hasClaimedMintlistBlob;

    /*//////////////////////////////////////////////////////////////
                            VRGDA INPUT STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Timestamp for the start of minting.
    uint256 public immutable mintStart;

    /// @notice Number of blobs minted from goo.
    uint128 public numMintedFromGoo;

    /*//////////////////////////////////////////////////////////////
                         STANDARD BLOB STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Id of the most recently minted blob.
    /// @dev Will be 0 if no blobs have been minted yet.
    uint128 public lastUsedId;

    /// @notice The number of blobs minted to the reserves.
    uint256 public numMintedForReserves;

    /*//////////////////////////////////////////////////////////////
                          BLOB REVEAL STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct holding data required for blob reveals.
    struct BlobRevealsData {
        // Last randomness obtained from the rand provider.
        uint64 randomSeed;
        // Next reveal cannot happen before this timestamp.
        uint64 nextRevealTimestamp;
        // Id of latest blob which has been revealed so far.
        uint64 lastRevealedId;
        // Remaining blobs to be revealed with the current seed.
        uint56 toBeRevealed;
        // Whether we are waiting to receive a seed from Chainlink.
        bool waitingForSeed;
    }

    /// @notice Data about the current state of blob reveals.
    BlobRevealsData public blobRevealsData;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event GooBalanceUpdated(address indexed user, uint256 newGooBalance);

    event BlobClaimed(address indexed user, uint256 indexed blobId);
    event BlobPurchased(address indexed user, uint256 indexed blobId, uint256 price);
    event ReservedBlobsMinted(address indexed user, uint256 lastMintedBlobId, uint256 numBlobsEach);

    event RandomnessFulfilled(uint256 randomness);
    event RandomnessRequested(address indexed user, uint256 toBeRevealed);
    event RandProviderUpgraded(address indexed user, RandProvider indexed newRandProvider);

    event BlobsRevealed(address indexed user, uint256 numBlobs, uint256 lastRevealedId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProof();
    error AlreadyClaimed();
    error MintStartPending();

    error SeedPending();
    error RevealsPending();
    error RequestTooEarly();
    error ZeroToBeRevealed();
    error NotRandProvider();

    error ReserveImbalance();

    error PriceExceededMax(uint256 currentPrice);

    error NotEnoughRemainingToBeRevealed(uint256 totalRemainingToBeRevealed);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets VRGDA parameters, mint config, relevant addresses, and URIs.
    /// @param _merkleRoot Merkle root of mint mintlist.
    /// @param _mintStart Timestamp for the start of the VRGDA mint.
    /// @param _goo Address of the Goo contract.
    /// @param _team Address of the team reserve.
    /// @param _community Address of the community reserve.
    /// @param _randProvider Address of the randomness provider.
    /// @param _baseUri Base URI for revealed blobs.
    /// @param _unrevealedUri URI for unrevealed blobs.
    constructor(
        // Mint config:
        bytes32 _merkleRoot,
        uint256 _mintStart,
        // Addresses:
        Goo _goo,
        address _team,
        address _community,
        RandProvider _randProvider,
        // URIs:
        string memory _baseUri,
        string memory _unrevealedUri
    )
        ERC721Checkpointable("Goo Blobs", "BLOBS") // TODO: get name
        Owned(msg.sender)
        LogisticVRGDA(
            69.42e18, // Target price.
            0.31e18, // Price decay percent.
            // Max blobs mintable via VRGDA.
            toWadUnsafe(MAX_MINTABLE),
            0.0023e18 // Time scale.
        )
    {
        mintStart = _mintStart;
        merkleRoot = _merkleRoot;

        goo = _goo;
        team = _team;
        community = _community;
        randProvider = _randProvider;

        BASE_URI = _baseUri;
        UNREVEALED_URI = _unrevealedUri;

        // Reveal for initial mint must wait a day from the start of the mint.
        blobRevealsData.nextRevealTimestamp = uint64(_mintStart + 1 days);
    }

    /*//////////////////////////////////////////////////////////////
                          MINTLIST CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim from mintlist, using a merkle proof.
    /// @dev Function does not directly enforce the MINTLIST_SUPPLY limit for gas efficiency. The
    /// limit is enforced during the creation of the merkle proof, which will be shared publicly.
    /// @param proof Merkle proof to verify the sender is mintlisted.
    /// @return blobId The id of the blob that was claimed.
    function claimBlob(bytes32[] calldata proof) external returns (uint256 blobId) {
        // If minting has not yet begun, revert.
        if (mintStart > block.timestamp) revert MintStartPending();

        // If the user has already claimed, revert.
        if (hasClaimedMintlistBlob[msg.sender]) revert AlreadyClaimed();

        // If the user's proof is invalid, revert.
        if (!MerkleProofLib.verify(proof, merkleRoot, keccak256(abi.encodePacked(msg.sender)))) revert InvalidProof();

        hasClaimedMintlistBlob[msg.sender] = true;

        unchecked {
            // Overflow should be impossible due to supply cap of 10,000.
            emit BlobClaimed(msg.sender, blobId = ++lastUsedId);
        }

        _mint(msg.sender, blobId);
    }

    /*//////////////////////////////////////////////////////////////
                              MINTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint a blob, paying with goo.
    /// @param maxPrice Maximum price to pay to mint the blob.
    /// @return blobId The id of the blob that was minted.
    function mintFromGoo(uint256 maxPrice) external returns (uint256 blobId) {
        // No need to check if we're at MAX_MINTABLE,
        // blobPrice() will revert once we reach it due to its
        // logistic nature. It will also revert prior to the mint start.
        uint256 currentPrice = blobPrice();

        // If the current price is above the user's specified max, revert.
        if (currentPrice > maxPrice) revert PriceExceededMax(currentPrice);

        // Decrement the user's goo balance by the current price
        // TODO: check if team is the correct recipient. same address that receives the team blobs?
        goo.transferFrom(msg.sender, address(team), currentPrice);

        unchecked {
            ++numMintedFromGoo; // Overflow should be impossible due to the supply cap.

            emit BlobPurchased(msg.sender, blobId = ++lastUsedId, currentPrice);
        }

        _mint(msg.sender, blobId);
    }

    /// @notice Blob pricing in terms of goo.
    /// @dev Will revert if called before minting starts
    /// or after all blobs have been minted via VRGDA.
    /// @return Current price of a blob in terms of goo.
    function blobPrice() public view returns (uint256) {
        // We need checked math here to cause underflow
        // before minting has begun, preventing mints.
        uint256 timeSinceStart = block.timestamp - mintStart;

        return getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), numMintedFromGoo);
    }

    /*//////////////////////////////////////////////////////////////
                            RANDOMNESS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Request a new random seed for revealing blobs.
    /// @dev Can only be called every 24 hours at the earliest.
    function requestRandomSeed() external returns (bytes32) {
        uint256 nextRevealTimestamp = blobRevealsData.nextRevealTimestamp;

        // A new random seed cannot be requested before the next reveal timestamp.
        if (block.timestamp < nextRevealTimestamp) revert RequestTooEarly();

        // A random seed can only be requested when all blobs from the previous seed have been revealed.
        // This prevents a user from requesting additional randomness in hopes of a more favorable outcome.
        if (blobRevealsData.toBeRevealed != 0) revert RevealsPending();

        unchecked {
            // Prevent revealing while we wait for the seed.
            blobRevealsData.waitingForSeed = true;

            // Compute the number of blobs to be revealed with the seed.
            uint256 toBeRevealed = lastUsedId - blobRevealsData.lastRevealedId;

            // Ensure that there are more than 0 blobs to be revealed,
            // otherwise the contract could waste LINK revealing nothing.
            if (toBeRevealed == 0) revert ZeroToBeRevealed();

            // Lock in the number of blobs to be revealed from seed.
            blobRevealsData.toBeRevealed = uint56(toBeRevealed);

            // We want at most one batch of reveals every 24 hours.
            // Timestamp overflow is impossible on human timescales.
            blobRevealsData.nextRevealTimestamp = uint64(nextRevealTimestamp + 1 days);

            emit RandomnessRequested(msg.sender, toBeRevealed);
        }

        // Call out to the randomness provider.
        return randProvider.requestRandomBytes();
    }

    /// @notice Callback from rand provider. Sets randomSeed. Can only be called by the rand provider.
    /// @param randomness The 256 bits of verifiable randomness provided by the rand provider.
    function acceptRandomSeed(bytes32, uint256 randomness) external {
        // The caller must be the randomness provider, revert in the case it's not.
        if (msg.sender != address(randProvider)) revert NotRandProvider();

        // The unchecked cast to uint64 is equivalent to moduloing the randomness by 2**64.
        blobRevealsData.randomSeed = uint64(randomness); // 64 bits of randomness is plenty.

        blobRevealsData.waitingForSeed = false; // We have the seed now, open up reveals.

        emit RandomnessFulfilled(randomness);
    }

    /// @notice Upgrade the rand provider contract. Useful if current VRF is sunset.
    /// @param newRandProvider The new randomness provider contract address.
    function upgradeRandProvider(RandProvider newRandProvider) external onlyOwner {
        // Revert if waiting for seed, so we don't interrupt requests in flight.
        if (blobRevealsData.waitingForSeed) revert SeedPending();

        randProvider = newRandProvider; // Update the randomness provider.

        emit RandProviderUpgraded(msg.sender, newRandProvider);
    }

    /*//////////////////////////////////////////////////////////////
                          BLOB REVEAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Knuth shuffle to progressively reveal
    /// new blobs using entropy from a random seed.
    /// @param numBlobs The number of blobs to reveal.
    function revealBlobs(uint256 numBlobs) external {
        uint256 randomSeed = blobRevealsData.randomSeed;

        uint256 lastRevealedId = blobRevealsData.lastRevealedId;

        uint256 totalRemainingToBeRevealed = blobRevealsData.toBeRevealed;

        // Can't reveal if we're still waiting for a new seed.
        if (blobRevealsData.waitingForSeed) revert SeedPending();

        // Can't reveal more blobs than are currently remaining to be revealed with the seed.
        if (numBlobs > totalRemainingToBeRevealed) revert NotEnoughRemainingToBeRevealed(totalRemainingToBeRevealed);

        // Implements a Knuth shuffle. If something in
        // here can overflow, we've got bigger problems.
        unchecked {
            for (uint256 i = 0; i < numBlobs; ++i) {
                /*//////////////////////////////////////////////////////////////
                                      DETERMINE RANDOM SWAP
                //////////////////////////////////////////////////////////////*/

                // Number of ids that have not been revealed.
                uint256 remainingIds = MAX_SUPPLY - lastRevealedId;

                // Randomly pick distance for swap.
                uint256 distance = randomSeed % remainingIds;

                // Current id is consecutive to last reveal.
                uint256 currentId = ++lastRevealedId;

                // Select swap id, adding distance to next reveal id.
                uint256 swapId = currentId + distance;

                /*//////////////////////////////////////////////////////////////
                                       GET INDICES FOR IDS
                //////////////////////////////////////////////////////////////*/

                // Get the index of the swap id.
                uint64 swapIndex =
                    getBlobData[swapId].idx == 0
                    ? uint64(swapId) // Hasn't been shuffled before.
                    : getBlobData[swapId].idx; // Shuffled before.

                // Get the index of the current id.
                uint64 currentIndex =
                    getBlobData[currentId].idx == 0
                    ? uint64(currentId) // Hasn't been shuffled before.
                    : getBlobData[currentId].idx; // Shuffled before.

                /*//////////////////////////////////////////////////////////////
                                        SWAP INDICES
                //////////////////////////////////////////////////////////////*/

                // Swap the index and multiple of the current id.
                getBlobData[currentId].idx = swapIndex;
                // Swap the index of the swap id.
                getBlobData[swapId].idx = currentIndex;

                /*//////////////////////////////////////////////////////////////
                                       UPDATE RANDOMNESS
                //////////////////////////////////////////////////////////////*/

                // Update the random seed to choose a new distance for the next iteration.
                // It is critical that we cast to uint64 here, as otherwise the random seed
                // set after calling revealBlobs(1) thrice would differ from the seed set
                // after calling revealBlobssingle time. This would enable an attacker
                // to choose from a number of different seeds and use whichever is most favorable.
                // Equivalent to randomSeed = uint64(uint256(keccak256(abi.encodePacked(randomSeed))))
                assembly {
                    mstore(0, randomSeed) // Store the random seed in scratch space.

                    // Moduloing by 2 ** 64 is equivalent to a uint64 cast.
                    randomSeed := mod(keccak256(0, 32), exp(2, 64))
                }
            }

            // Update all relevant reveal state.
            blobRevealsData.randomSeed = uint64(randomSeed);
            blobRevealsData.lastRevealedId = uint64(lastRevealedId);
            blobRevealsData.toBeRevealed = uint56(totalRemainingToBeRevealed - numBlobs);

            emit BlobsRevealed(msg.sender, numBlobs, lastRevealedId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                URI LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a token's URI if it has been minted.
    /// @param blobId The id of the token to get the URI for.
    function tokenURI(uint256 blobId) public view virtual override returns (string memory) {
        // Between 0 and lastRevealed are revealed normal blobs.
        if (blobId <= blobRevealsData.lastRevealedId) {
            if (blobId == 0) revert("NOT_MINTED"); // 0 is not a valid id for blob.

            return string.concat(BASE_URI, uint256(getBlobData[blobId].idx).toString());
        }

        // Between lastRevealed + 1 and lastUsedId are minted but not revealed.
        if (blobId <= lastUsedId) return UNREVEALED_URI;

        // Between lastUsedId and MAX_SUPPLY are unminted.
        revert("NOT_MINTED");
    }

    /*//////////////////////////////////////////////////////////////
                     RESERVED BLOBS MINTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint a number of blobs to the reserves.
    /// @param numBlobsEach The number of blobs to mint to each reserve.
    /// @dev Blobs minted to reserves cannot comprise more than 20% of the sum of
    /// the supply of goo minted blobs and the supply of blobs minted to reserves.
    function mintReservedBlobs(uint256 numBlobsEach) external returns (uint256 lastMintedBlobId) {
        unchecked {
            // Optimistically increment numMintedForReserves, may be reverted below.
            // Overflow in this calculation is possible but numBlobsEach would have to
            // be so large that it would cause the loop in _batchMint to run out of gas quickly.
            uint256 newNumMintedForReserves = numMintedForReserves += (numBlobsEach * 2);

            // Ensure that after this mint blobs minted to reserves won't comprise more than 20% of
            // the sum of the supply of goo minted blobs and the supply of blobs minted to reserves.
            if (newNumMintedForReserves > (numMintedFromGoo + newNumMintedForReserves) / 5) revert ReserveImbalance();
        }

        // Mint numBlobsEach blobs to both the team and community reserve.
        lastMintedBlobId = _batchMint(team, numBlobsEach, lastUsedId);
        lastMintedBlobId = _batchMint(community, numBlobsEach, lastMintedBlobId);

        lastUsedId = uint128(lastMintedBlobId); // Set lastUsedId.

        emit ReservedBlobsMinted(msg.sender, lastMintedBlobId, numBlobsEach);
    }
}
