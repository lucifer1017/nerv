// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAgenticID {
    function ownerOf(uint256 tokenId) external view returns (address);
}

abstract contract ReentrancyGuard {
    uint256 private _locked = 1;
    error Reentrancy();
    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }
}

/// @title NervRoyaltyVault
/// @notice Accepts native OG payments per strategy iNFT and splits between an
///         explicitly-registered creator (the publisher) and the iNFT's current
///         owner. Decoupling the creator from AgenticID.tokenCreator means the
///         payout is correct regardless of who minted the token.
contract NervRoyaltyVault is ReentrancyGuard {
    IAgenticID public immutable agenticId;
    address public immutable admin;
    uint16 public constant BPS_DENOMINATOR = 10000;

    struct Strategy {
        address creator; // explicit payout beneficiary (the publisher)
        uint16 creatorBps; // creator share; remainder -> current iNFT owner
        bool set;
    }

    mapping(uint256 => Strategy) public strategies;
    mapping(uint256 => uint256) public totalDistributed;

    event StrategySet(
        uint256 indexed tokenId,
        address indexed creator,
        uint16 creatorBps
    );
    event Distributed(
        uint256 indexed tokenId,
        address indexed payer,
        address creator,
        address currentOwner,
        uint256 totalAmount,
        uint256 creatorAmount,
        uint256 ownerAmount
    );

    error ZeroAddress();
    error NotAdmin();
    error BpsTooHigh();
    error NoPayment();
    error StrategyNotSet();
    error TransferFailed();

    constructor(address agenticIdAddress) {
        if (agenticIdAddress == address(0)) revert ZeroAddress();
        agenticId = IAgenticID(agenticIdAddress);
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /// @notice Declare who gets paid for a tokenId and the creator share.
    /// @param creatorBps 10000 = 100% to creator (owner gets nothing).
    ///                   8000  = 80% creator / 20% current owner, etc.
    function setStrategy(
        uint256 tokenId,
        address creator,
        uint16 creatorBps
    ) external onlyAdmin {
        if (creator == address(0)) revert ZeroAddress();
        if (creatorBps > BPS_DENOMINATOR) revert BpsTooHigh();
        strategies[tokenId] = Strategy({
            creator: creator,
            creatorBps: creatorBps,
            set: true
        });
        emit StrategySet(tokenId, creator, creatorBps);
    }

    /// @notice Pay a royalty for a tokenId. Splits atomically.
    function distribute(uint256 tokenId) external payable nonReentrant {
        if (msg.value == 0) revert NoPayment();
        Strategy memory s = strategies[tokenId];
        if (!s.set) revert StrategyNotSet();

        uint256 creatorAmount = (msg.value * s.creatorBps) / BPS_DENOMINATOR;
        uint256 ownerAmount = msg.value - creatorAmount;

        // EFFECTS before INTERACTIONS (checks-effects-interactions)
        totalDistributed[tokenId] += msg.value;

        // INTERACTIONS
        address currentOwner = address(0);
        if (creatorAmount > 0) _pay(s.creator, creatorAmount);
        if (ownerAmount > 0) {
            currentOwner = agenticId.ownerOf(tokenId); // only queried when needed
            _pay(currentOwner, ownerAmount);
        }

        emit Distributed(
            tokenId,
            msg.sender,
            s.creator,
            currentOwner,
            msg.value,
            creatorAmount,
            ownerAmount
        );
    }

    function getStrategy(
        uint256 tokenId
    ) external view returns (address creator, uint16 creatorBps, bool set) {
        Strategy memory s = strategies[tokenId];
        return (s.creator, s.creatorBps, s.set);
    }

    function _pay(address to, uint256 amount) private {
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
