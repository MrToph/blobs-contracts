// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Owned} from "solmate/auth/Owned.sol";

import {Blobs} from "../Blobs.sol";

/// @title Gobbler Reserve
/// @author FrankieIsLost <frankie@paradigm.xyz>
/// @author transmissions11 <t11s@paradigm.xyz>
/// @notice Reserves blobs for an owner while keeping any goo produced.
contract BlobReserve is Owned {
    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Blobs contract address.
    Blobs public immutable blobs;

    /// @notice Sets the addresses of relevant contracts and users.
    /// @param _blobs The address of the Blobs contract.
    /// @param _owner The address of the owner of Blob Reserve.
    constructor(Blobs _blobs, address _owner) Owned(_owner) {
        blobs = _blobs;
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraw blobs from the reserve.
    /// @param to The address to transfer the blobs to.
    /// @param ids The ids of the blobs to transfer.
    function withdraw(address to, uint256[] calldata ids) external onlyOwner {
        // This is quite inefficient, but that's fine, it's not a hot path.
        unchecked {
            for (uint256 i = 0; i < ids.length; ++i) {
                blobs.transferFrom(address(this), to, ids[i]);
            }
        }
    }
}
