// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ITriplV5ExternalCollection {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Pull-based quote rewards for a fixed external ERC-721 snapshot.
/// @dev The snapshot is an immutable commitment. The contract deliberately
/// does not infer collection completeness or call the collection during fee
/// recording. A client supplies an index and Merkle proof at claim time; the
/// current owner of that NFT receives every unclaimed whole quote unit.
contract TriplV5CollectionRewards is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 public constant MODE_ALL = 1;
    uint8 public constant MODE_FIRST_N = 2;
    uint8 public constant MODE_EXPLICIT = 3;
    uint256 public constant MAX_CLAIM_TOKENS = 64;

    error InvalidConfiguration();
    error InvalidProof();
    error Unauthorized();
    error NothingToClaim();
    error InexactTransfer();

    ITriplV5ExternalCollection public immutable collection;
    IERC20Metadata public immutable quote;
    address public immutable poolManager;
    address public immutable vault;
    bytes32 public immutable snapshotRoot;
    uint256 public immutable tokenCount;
    uint8 public immutable eligibilityMode;
    uint256 public immutable snapshotBlock;
    bytes32 public immutable snapshotBlockHash;
    bytes32 public immutable manifestHash;
    string public snapshotURI;

    mapping(uint256 => uint256) public tokenCursor;

    uint256 public cumulativeRewardPerToken;
    uint256 public pendingReward;
    uint256 public totalFunded;
    uint256 public totalClaimed;
    uint256 public accountedLiabilities;

    event RewardNotified(uint256 indexed amount, uint256 indexed distributed, uint256 pending);
    event RewardClaimed(uint256 indexed tokenId, address indexed holder, uint256 amount);

    constructor(
        address collection_,
        address quote_,
        address poolManager_,
        address vault_,
        bytes32 snapshotRoot_,
        uint256 tokenCount_,
        bytes32 manifestHash_,
        uint8 eligibilityMode_,
        uint256 snapshotBlock_,
        bytes32 snapshotBlockHash_,
        string memory snapshotURI_
    ) {
        if (
            collection_ == address(0) || collection_.code.length == 0 || quote_ == address(0)
                || quote_.code.length == 0 || poolManager_ == address(0)
                || vault_ == address(0) || snapshotRoot_ == bytes32(0) || tokenCount_ == 0
                || manifestHash_ == bytes32(0) || snapshotBlock_ == 0
                || snapshotBlockHash_ == bytes32(0) || bytes(snapshotURI_).length == 0
                || (eligibilityMode_ != MODE_ALL && eligibilityMode_ != MODE_FIRST_N
                    && eligibilityMode_ != MODE_EXPLICIT)
        ) revert InvalidConfiguration();
        try IERC20Metadata(quote_).decimals() returns (uint8 decimals) {
            if (decimals < 6 || decimals > 18) revert InvalidConfiguration();
        } catch {
            revert InvalidConfiguration();
        }
        collection = ITriplV5ExternalCollection(collection_);
        quote = IERC20Metadata(quote_);
        poolManager = poolManager_;
        vault = vault_;
        snapshotRoot = snapshotRoot_;
        tokenCount = tokenCount_;
        eligibilityMode = eligibilityMode_;
        snapshotBlock = snapshotBlock_;
        snapshotBlockHash = snapshotBlockHash_;
        manifestHash = manifestHash_;
        snapshotURI = snapshotURI_;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert Unauthorized();
        _;
    }

    /// @notice Amount currently available for one committed token ID.
    function pendingFor(uint256 tokenId) public view returns (uint256 amount) {
        uint256 cursor = tokenCursor[tokenId];
        if (cumulativeRewardPerToken > cursor) amount = cumulativeRewardPerToken - cursor;
    }

    function pendingFor(uint256 tokenId, uint256 index, bytes32[] calldata proof)
        external
        view
        returns (uint256 amount)
    {
        if (_verify(tokenId, index, proof)) amount = pendingFor(tokenId);
    }

    function verifySnapshot(uint256 tokenId, uint256 index, bytes32[] calldata proof)
        public
        view
        returns (bool)
    {
        return _verify(tokenId, index, proof);
    }

    /// @notice Accept quote already transferred by the fee vault.
    /// Donations remain unaccounted surplus and cannot increase this index.
    function notifyReward(uint256 amount) external onlyVault {
        if (amount == 0 || amount > type(uint256).max - accountedLiabilities) {
            revert InvalidConfiguration();
        }
        if (quote.balanceOf(address(this)) < accountedLiabilities + amount) {
            revert InexactTransfer();
        }
        uint256 previousIndex = cumulativeRewardPerToken;
        totalFunded += amount;
        accountedLiabilities += amount;
        cumulativeRewardPerToken = totalFunded / tokenCount;
        pendingReward = totalFunded % tokenCount;
        uint256 distributed = (cumulativeRewardPerToken - previousIndex) * tokenCount;
        emit RewardNotified(amount, distributed, pendingReward);
    }

    function claim(uint256 tokenId, uint256 index, bytes32[] calldata proof)
        external
        nonReentrant
        returns (uint256 amount)
    {
        amount = _claimToken(tokenId, index, proof, msg.sender);
        if (amount == 0) revert NothingToClaim();
    }

    function claimMany(
        uint256[] calldata tokenIds,
        uint256[] calldata indices,
        bytes32[][] calldata proofs
    ) external nonReentrant returns (uint256 total) {
        if (
            tokenIds.length == 0 || tokenIds.length > MAX_CLAIM_TOKENS
                || tokenIds.length != indices.length || tokenIds.length != proofs.length
        ) revert InvalidConfiguration();
        for (uint256 i; i < tokenIds.length; ++i) {
            total += _claimToken(tokenIds[i], indices[i], proofs[i], msg.sender);
        }
        if (total == 0) revert NothingToClaim();
    }

    function _claimToken(
        uint256 tokenId,
        uint256 index,
        bytes32[] calldata proof,
        address claimant
    ) private returns (uint256 amount) {
        if (!_verify(tokenId, index, proof)) revert InvalidProof();
        address owner;
        try collection.ownerOf(tokenId) returns (address value) {
            owner = value;
        } catch {
            revert Unauthorized();
        }
        if (owner == address(0) || owner != claimant) revert Unauthorized();
        uint256 cursor = tokenCursor[tokenId];
        if (cumulativeRewardPerToken <= cursor) return 0;
        amount = cumulativeRewardPerToken - cursor;
        tokenCursor[tokenId] = cumulativeRewardPerToken;
        accountedLiabilities -= amount;
        totalClaimed += amount;
        _pushExact(owner, amount);
        emit RewardClaimed(tokenId, owner, amount);
    }

    function _verify(uint256 tokenId, uint256 index, bytes32[] calldata proof)
        private
        view
        returns (bool)
    {
        if (index >= tokenCount || proof.length > 32) return false;
        bytes32 computed = _hashLeaf(index, tokenId);
        for (uint256 i; i < proof.length; ++i) {
            bytes32 sibling = proof[i];
            computed = (index & (1 << i)) == 0
                ? _hashPair(computed, sibling)
                : _hashPair(sibling, computed);
        }
        return computed == snapshotRoot;
    }

    function _hashPair(bytes32 left, bytes32 right) private pure returns (bytes32) {
        (left, right) = left < right ? (left, right) : (right, left);
        assembly ("memory-safe") {
            mstore(0x00, left)
            mstore(0x20, right)
            left := keccak256(0x00, 0x40)
        }
        return left;
    }

    function _hashLeaf(uint256 index, uint256 tokenId) private pure returns (bytes32 leaf) {
        assembly ("memory-safe") {
            mstore(0x00, index)
            mstore(0x20, tokenId)
            leaf := keccak256(0x00, 0x40)
        }
    }

    function _pushExact(address to, uint256 amount) private {
        uint256 beforeSender = quote.balanceOf(address(this));
        uint256 beforeReceiver = quote.balanceOf(to);
        IERC20(address(quote)).safeTransfer(to, amount);
        if (
            beforeSender < quote.balanceOf(address(this))
                || beforeSender - quote.balanceOf(address(this)) != amount
                || quote.balanceOf(to) < beforeReceiver
                || quote.balanceOf(to) - beforeReceiver != amount
        ) revert InexactTransfer();
    }
}
