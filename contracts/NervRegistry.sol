// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAgenticID {
    function tokenCreator(uint256 tokenId) external view returns (address);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title NervRegistry
/// @notice Immutable mapping: AgenticID tokenId -> 0G Storage rootHash of the
///         encrypted StrategyConfig blob. Lets anyone resolve "what does iNFT
///         #N do?" by reading rootHashOf(tokenId) and fetching from 0G directly.
contract NervRegistry {
    IAgenticID public immutable agenticId;
    address public immutable admin;

    struct Entry {
        bytes32 rootHash;     // 0G Storage rootHash (already 32 bytes — pass directly)
        address registrant;
        uint64 registeredAt;
    }

    mapping(uint256 => Entry) public entries;

    event Registered(
        uint256 indexed tokenId,
        bytes32 indexed rootHash,
        address indexed registrant,
        uint64 registeredAt
    );

    error ZeroAddress();
    error ZeroRootHash();
    error AlreadyRegistered();
    error NotAuthorized();

    constructor(address agenticIdAddress) {
        if (agenticIdAddress == address(0)) revert ZeroAddress();
        agenticId = IAgenticID(agenticIdAddress);
        admin = msg.sender; // your backend deployer wallet
    }

    /// @notice Bind a strategy blob to a tokenId. One-shot; immutable thereafter.
    /// @dev Callable by the backend admin (custodial mint) OR the iNFT's
    ///      on-chain creator (trustless mint). Re-publishing = mint a NEW tokenId.
    function register(uint256 tokenId, bytes32 rootHash) external {
        if (rootHash == bytes32(0)) revert ZeroRootHash();
        if (entries[tokenId].registeredAt != 0) revert AlreadyRegistered();
        if (msg.sender != admin && msg.sender != agenticId.tokenCreator(tokenId)) {
            revert NotAuthorized();
        }
        entries[tokenId] = Entry({
            rootHash: rootHash,
            registrant: msg.sender,
            registeredAt: uint64(block.timestamp)
        });
        emit Registered(tokenId, rootHash, msg.sender, uint64(block.timestamp));
    }

    function rootHashOf(uint256 tokenId) external view returns (bytes32) {
        return entries[tokenId].rootHash;
    }

    function isRegistered(uint256 tokenId) external view returns (bool) {
        return entries[tokenId].registeredAt != 0;
    }
}