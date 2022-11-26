// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {IGobblers} from "./IGobblers.sol";
import {IGooSalesReceiver} from "./IGooSalesReceiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Goo} from "./Goo.sol";

/// @title Blobs NFT
/// @notice An experimental decentralized art companion project to ArtBlobs
contract GobblersTreasury is IGooSalesReceiver, Owned, ERC721TokenReceiver, ERC1155TokenReceiver {
    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/
    IGobblers public immutable gobblers;
    IERC20 public immutable goo;
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
        goo = IERC20(IGobblers(_gobblers).goo());
    }

    // after some time, when the DAO is sufficiemtly decentralized to not make 51% attacks economically infeasible, the treasury has full control over the gobblers in the vault
    modifier timeLocked() {
        if (block.timestamp < unlockTimestamp) {
            revert TimeLocked();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            OPERATION LOGIC
    //////////////////////////////////////////////////////////////*/
    function setTimelock(uint40 _newTimelockDuration) external onlyOwner {
        // prevent attack to reduce this to too low of a value
        _newTimelockDuration = _newTimelockDuration < 60 days ? 60 days : _newTimelockDuration;
        // overflow the new timestamp computation to protect against attacks
        emit TimeLockUpdated(unlockTimestamp = uint40(block.timestamp) + _newTimelockDuration);
    }

    /*//////////////////////////////////////////////////////////////
                            OPEN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function addGoo() external override {
        uint256 toAdd = goo.balanceOf(address(this));
        if (toAdd > 0) {
            IGobblers(gobblers).addGoo(toAdd);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            NON_TIMELOCKED DAO FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function removeGooAndTransfer(uint256 toWithdraw, uint256 toSend, address receiver) external onlyOwner timeLocked {
        if (toWithdraw > 0) {
            IGobblers(gobblers).removeGoo(toSend);
        }
        if (toSend > 0 && receiver != address(0) && receiver != address(this)) {
            goo.transfer(receiver, toSend);
        }
    }

    function mintLegendaryGobbler(uint256[] calldata gobblerIds) external returns (uint256 gobblerId) {
        gobblerId = gobblers.mintLegendaryGobbler(gobblerIds);
    }

    function mintFromGoo(uint256 maxPrice) external returns (uint256 gobblerId) {
        // TODO: implement better strategy. right now it's max bidding (buy as soon as possible)
        gobblerId = gobblers.mintFromGoo({ maxPrice: maxPrice, useVirtualBalance: true });
    }

    /*//////////////////////////////////////////////////////////////
                        TIMELOCKED DAO FUNCTIONS
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
