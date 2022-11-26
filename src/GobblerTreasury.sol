// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;


import {Owned} from "solmate/auth/Owned.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";



import {Goo} from "./Goo.sol";

/// @title Blobs NFT
/// @notice An experimental decentralized art companion project to ArtBlobs
contract Blobs is ERC721Checkpointable, Owned, ERC721TokenReceiver, ERC1155TokenReceiver {
    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/
    uint40 public unlockTimestamp;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event TimeLockUpdated(uint40 newUnlockTimestamp);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TimeLocked();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    // initialize owner to the DAO treasury upon deployment
    constructor(address _treasury) Owner(_treasury) {
      unlockTimestamp = block.timestamp + 180 days;
    }

    // after some time, when the DAO is sufficiemtly decentralized to not make 51% attacks economically infeasible, the treasury has full control over the gobblers in the vault
    modifier timeLocked() {
        if(block.timestamp < unlockTimestamp) {
            revert TimeLocked();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            LOGIC
    //////////////////////////////////////////////////////////////*/
    function changeTimelock(uint40 _newTimelockDuration) external onlyOwner {
      // prevent attack to reduce this to too low of a value
      _newTimelockDuration = _newTimelockDuration < 60 days ? 60 days : _newTimelockDuration;
      emit TimeLockUpdated(unlockTimestamp = block.timestamp + _newTimelockDuration);
    }

     function approve(address spender, uint256 id) external onlyOwner timeLocked {

     }
}
