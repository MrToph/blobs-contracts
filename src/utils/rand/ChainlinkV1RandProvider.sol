// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {VRFConsumerBase} from "chainlink/v0.8/VRFConsumerBase.sol";

import {Blobs} from "../../Blobs.sol";

import {RandProvider} from "./RandProvider.sol";

/// @title Chainlink V1 Randomness Provider.
/// @author FrankieIsLost <frankie@paradigm.xyz>
/// @author transmissions11 <t11s@paradigm.xyz>
/// @notice RandProvider wrapper around Chainlink VRF v1.
contract ChainlinkV1RandProvider is RandProvider, VRFConsumerBase {
    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the Blobs contract.
    Blobs public immutable blobs;

    /*//////////////////////////////////////////////////////////////
                            VRF CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @dev Public key to generate randomness against.
    bytes32 internal immutable chainlinkKeyHash;

    /// @dev Fee required to fulfill a VRF request.
    uint256 internal immutable chainlinkFee;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotBlobs();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets relevant addresses and VRF parameters.
    /// @param _blobs Address of the Blobs contract.
    /// @param _vrfCoordinator Address of the VRF coordinator.
    /// @param _linkToken Address of the LINK token contract.
    /// @param _chainlinkKeyHash Public key to generate randomness against.
    /// @param _chainlinkFee Fee required to fulfill a VRF request.
    constructor(
        Blobs _blobs,
        address _vrfCoordinator,
        address _linkToken,
        bytes32 _chainlinkKeyHash,
        uint256 _chainlinkFee
    )
        VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        blobs = _blobs;

        chainlinkKeyHash = _chainlinkKeyHash;
        chainlinkFee = _chainlinkFee;
    }

    /// @notice Request random bytes from Chainlink VRF. Can only by called by the Blobs contract.
    function requestRandomBytes() external returns (bytes32 requestId) {
        // The caller must be the Blobs contract, revert otherwise.
        if (msg.sender != address(blobs)) revert NotBlobs();

        emit RandomBytesRequested(requestId);

        // Will revert if we don't have enough LINK to afford the request.
        return requestRandomness(chainlinkKeyHash, chainlinkFee);
    }

    /// @dev Handles VRF response by calling back into the Blobs contract.
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        emit RandomBytesReturned(requestId, randomness);

        blobs.acceptRandomSeed(requestId, randomness);
    }
}
