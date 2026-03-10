// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library MerkleProof {
    error InvalidProof();

    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        uint256 proofLength = proof.length;

        for (uint256 i = 0; i < proofLength; ) {
            computedHash = _hashPair(computedHash, proof[i]);
            unchecked {
                ++i;
            }
        }

        if (computedHash != root) {
            revert InvalidProof();
        }
        return true;
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
