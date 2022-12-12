// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {IGobblers} from "./IGobblers.sol";
import {IGooSalesReceiver} from "./IGooSalesReceiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibGOO} from "goo-issuance/LibGOO.sol";

import {Goo} from "art-gobblers/Goo.sol";

/// @title Blobs NFT
/// @notice An experimental decentralized art companion project to ArtBlobs
contract GobblersTreasury is IGooSalesReceiver, Owned, ERC721TokenReceiver, ERC1155TokenReceiver {
    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/
    IGobblers public immutable gobblers;
    IERC20 public immutable goo;
    uint40 public unlockTimestamp;
    uint80 public mintAveragingDays; // measured in days where 1.0 days = 1e18

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event TimeLockUpdated(uint40 newUnlockTimestamp);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TimeLocked();
    error MintNotEnoughGoo(uint256 currentGoo, uint256 requiredGoo);
    error MintNotProfitable(uint256 gooNoMint, uint256 gooWithMint);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    // initialize owner to the DAO treasury upon deployment
    constructor(address _treasury, address _gobblers) Owned(_treasury) {
        unlockTimestamp = uint40(block.timestamp) + 180 days;
        mintAveragingDays = 30e18; // if we mint now and end up with more goo in a month (on average), mint it
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
        _newTimelockDuration = _newTimelockDuration < 30 days ? 30 days : _newTimelockDuration;
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

    function mintLegendaryGobbler(uint256[] calldata gobblerIds) external returns (uint256 gobblerId) {
        gobblerId = gobblers.mintLegendaryGobbler(gobblerIds);
    }

    function mintGobbler() external returns (uint256 gobblerId) {
        checkMintGobbler();

        gobblerId = gobblers.mintFromGoo({ maxPrice: type(uint256).max, useVirtualBalance: true });
    }


    /*//////////////////////////////////////////////////////////////
                            NON_TIMELOCKED DAO FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function removeGooAndTransfer(uint256 toWithdraw, uint256 toSend, address receiver) external onlyOwner {
        if (toWithdraw > 0) {
            IGobblers(gobblers).removeGoo(toSend);
        }
        if (toSend > 0 && receiver != address(0) && receiver != address(this)) {
            goo.transfer(receiver, toSend);
        }
    }

    function setMintAveragingDays(uint80 daysScaled) external onlyOwner {
        mintAveragingDays = daysScaled;
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

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function checkMintGobbler() public view {
        uint256 averagingDays = mintAveragingDays;
        uint256 currentMintPrice = gobblers.gobblerPrice();
        uint256 currentGoo = gobblers.gooBalance(address(this));
        uint256 currentMultiple = gobblers.getUserEmissionMultiple(address(this));
        uint256 expectedMintMultiple = 7; // 7.329 in reality, but we round down to 7 because we need integers and we ignore the time of 0 multiplier from unrevleaed to reveal

        if(currentGoo < currentMintPrice) {
            revert MintNotEnoughGoo(currentGoo, currentMintPrice);
        }

        uint256 gooBalanceWithMint = LibGOO.computeGOOBalance(
            currentMultiple + expectedMintMultiple,
            currentGoo - currentMintPrice,
            averagingDays
        );
        uint256 gooBalanceNoMint = LibGOO.computeGOOBalance(
            currentMultiple,
            currentGoo,
            averagingDays
        );

        // averagingDays = type(uint80).max is max-bid, where the treasury will always mint if it can.
        // because if `t` is large only quadratic term is relevant and
        // (M + newGobbler) * t^2 >= M * t^2 will almost always be true
        if(gooBalanceWithMint < gooBalanceNoMint) {
            revert MintNotProfitable(gooBalanceNoMint, gooBalanceWithMint);
        }
    }
}
