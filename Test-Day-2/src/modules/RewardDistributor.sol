// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ITreasury.sol";
import "../libraries/MerkleProof.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/EIP712.sol";
import "../libraries/SignatureVerification.sol";

contract RewardDistributor is IRewardDistributor, ReentrancyGuard {

    bytes32 public merkleRoot;
    mapping(address => uint256) public claimedAmounts;
    mapping(address => bool) public claimers;
    uint256 public totalClaimed;

    address public governor;
    address public token;

    uint256 public claimDeadline;
    uint256 public nonce;

    modifier onlyGovernor() {
        if (msg.sender != governor) {
            revert NotGovernor();
        }
        _;
    }

    error NotGovernor();
    error AlreadyClaimed();
    error InvalidProof();
    error ClaimExpired();
    error InvalidAmount();
    error ZeroAddress();

    constructor(address _governor, address _token, uint256 _claimDeadline) {
        if (_governor == address(0) || _token == address(0)) {
            revert ZeroAddress();
        }
        governor = _governor;
        token = _token;
        claimDeadline = _claimDeadline;
        ReentrancyGuard.init();
    }

    function claim(
        address recipient,
        uint256 amount,
        uint256 claimNonce,
        bytes32[] calldata proof
    ) external nonReentrant {
        if (block.timestamp > claimDeadline) {
            revert ClaimExpired();
        }

        if (claimers[recipient]) {
            revert AlreadyClaimed();
        }

        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount, claimNonce));

        bytes32[] memory merkleProof = new bytes32[](proof.length);
        for (uint256 i = 0; i < proof.length; ) {
            merkleProof[i] = proof[i];
            unchecked {
                ++i;
            }
        }

        if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) {
            revert InvalidProof();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        claimers[recipient] = true;
        claimedAmounts[recipient] = amount;
        totalClaimed += amount;

        IERC20(token).transfer(recipient, amount);

        emit Claimed(recipient, amount, claimNonce);
    }

    function claimWithSignature(
        address recipient,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        if (block.timestamp > claimDeadline) {
            revert ClaimExpired();
        }
        if (block.timestamp > deadline) {
            revert ClaimExpired();
        }

        if (claimers[recipient]) {
            revert AlreadyClaimed();
        }

        bytes32 digest = EIP712.computeDigest(
            EIP712.hashClaim(recipient, amount, nonce++, deadline)
        );

        SignatureVerification.verify(digest, signature, governor);

        if (amount == 0) {
            revert InvalidAmount();
        }

        claimers[recipient] = true;
        claimedAmounts[recipient] = amount;
        totalClaimed += amount;

        IERC20(token).transfer(recipient, amount);

        emit Claimed(recipient, amount, nonce - 1);
    }

    function updateMerkleRoot(bytes32 newRoot) external onlyGovernor {
        merkleRoot = newRoot;
        emit MerkleRootUpdated(newRoot);
    }

    function updateClaimDeadline(uint256 newDeadline) external onlyGovernor {
        claimDeadline = newDeadline;
    }

    function getMerkleRoot() external view returns (bytes32) {
        return merkleRoot;
    }

    function hasClaimed(address recipient) external view returns (bool) {
        return claimers[recipient];
    }

    function getClaimedAmount(address recipient) external view returns (uint256) {
        return claimedAmounts[recipient];
    }

    function sweepDust(address tokenToSweep) external onlyGovernor {
        if (tokenToSweep == token) {
            uint256 balance = IERC20(tokenToSweep).balanceOf(address(this));
            uint256 available = balance - totalClaimed;
            if (available > 0) {
                IERC20(tokenToSweep).transfer(msg.sender, available);
            }
        } else {
            uint256 balance = IERC20(tokenToSweep).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokenToSweep).transfer(msg.sender, balance);
            }
        }
    }

    receive() external payable {}
}
