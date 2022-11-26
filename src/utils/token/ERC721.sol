// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/**
 * Base: https://github.com/artgobblers/art-gobblers/tree/a337353df07193225aad40e8d6659bd67b0abb20
 * Modifications:
 * - removed gobbler related fields from structures like emissionMultiples, balances, etc.
 * - added `totalSupply` as it's required for NounsGovernance: https://github.com/nounsDAO/nouns-monorepo/blob/fe099f0df11e5e4de81cc0cd6a2186d3c82135ed/packages/nouns-contracts/contracts/governance/NounsDAOInterfaces.sol#L442
 * - added `_beforeTokenTransfer` for ERC721Checkpointable to hook into
 */
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

/// @notice ERC721 implementation optimized for ArtGobblers by packing balanceOf/ownerOf with user/attribute data.
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) external view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                         GOBBLERS/ERC721 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct holding gobbler data.
    struct GobblerData {
        // The current owner of the gobbler.
        address owner;
        // Index of token after shuffle.
        uint64 idx;
    }

    /// @notice Maps gobbler ids to their data.
    mapping(uint256 => GobblerData) public getGobblerData;
    // @notice Maps an address to number of gobblers owned
    mapping(address => uint256) internal _balanceOf;
    uint256 public totalSupply;

    function ownerOf(uint256 id) external view returns (address owner) {
        require((owner = getGobblerData[id].owner) != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        return _balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) external {
        address owner = getGobblerData[id].owner;

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 id) external {
        _transferFrom(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id) external {
        _transferFrom(from, to, id);

        require(
            to.code.length == 0
                || ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "")
                    == ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data) external {
        _transferFrom(from, to, id);

        require(
            to.code.length == 0
                || ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data)
                    == ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x80ac58cd // ERC165 Interface ID for ERC721
            || interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL MINT & TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    function _transferFrom(address from, address to, uint256 id) internal {
        require(from == getGobblerData[id].owner, "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id], "NOT_AUTHORIZED"
        );

        _beforeTokenTransfer(from, to, id);

        delete getApproved[id];

        getGobblerData[id].owner = to;

        unchecked {
            _balanceOf[from] -= 1;
            _balanceOf[to] += 1;
        }

        emit Transfer(from, to, id);
    }

    function _mint(address to, uint256 id) internal {
        // Does not check if the token was already minted or the recipient is address(0)
        // because ArtGobblers.sol manages its ids in such a way that it ensures it won't
        // double mint and will only mint to safe addresses or msg.sender who cannot be zero.
        _beforeTokenTransfer(address(0), to, id);

        unchecked {
            ++_balanceOf[to];
            ++totalSupply;
        }

        getGobblerData[id].owner = to;

        emit Transfer(address(0), to, id);
    }

    function _batchMint(address to, uint256 amount, uint256 lastMintedId) internal returns (uint256) {
        // Doesn't check if the tokens were already minted or the recipient is address(0)
        // because ArtGobblers.sol manages its ids in such a way that it ensures it won't
        // double mint and will only mint to safe addresses or msg.sender who cannot be zero.

        unchecked {
            for (uint256 i = 0; i < amount; ++i) {
                _mint(to, ++lastMintedId);
            }
        }

        return lastMintedId;
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}
}
