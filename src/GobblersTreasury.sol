// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {IGobblers} from "./IGobblers.sol";

import {Goo} from "./Goo.sol";

/// @title Blobs NFT
/// @notice An experimental decentralized art companion project to ArtBlobs
contract GobblersTreasury is Owned, ERC721TokenReceiver, ERC1155TokenReceiver {
    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/
    IGobblers public immutable gobblers;
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
    constructor(address _treasury, address _gobblers) Owned(_treasury) {
        unlockTimestamp = uint40(block.timestamp) + 180 days;
        gobblers = IGobblers(_gobblers);
    }

    // after some time, when the DAO is sufficiemtly decentralized to not make 51% attacks economically infeasible, the treasury has full control over the gobblers in the vault
    modifier timeLocked() {
        if (block.timestamp < unlockTimestamp) {
            revert TimeLocked();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            LOGIC
    //////////////////////////////////////////////////////////////*/
    function setTimelock(uint40 _newTimelockDuration) external onlyOwner {
        // prevent attack to reduce this to too low of a value
        _newTimelockDuration = _newTimelockDuration < 60 days ? 60 days : _newTimelockDuration;
        // overflow the new timestamp computation to protect against attacks
        emit TimeLockUpdated(unlockTimestamp = uint40(block.timestamp) + _newTimelockDuration);
    }

    /*//////////////////////////////////////////////////////////////
                        TIMELOCKED GOBBLER LOGIC
    //////////////////////////////////////////////////////////////*/
    function approve(address spender, uint256 id) external onlyOwner timeLocked {
        gobblers.approve(spender, id);
    }

    function setApprovalForAll(address operator, bool approved) external onlyOwner timeLocked {
        gobblers.setApprovalForAll(operator, approved);
    }

    function transferFrom(address from, address to, uint256 id) external onlyOwner timeLocked {
        gobblers.transferFrom(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data)
        external
        onlyOwner
        timeLocked
    {
        gobblers.safeTransferFrom(from, to, id, data);
    }
}
