// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library SignatureVerification {
    error InvalidSignatureLength();
    error InvalidSignature();

    function verify(
        bytes32 digest,
        bytes calldata signature,
        address signer
    ) internal pure {
        if (signature.length != 65) {
            revert InvalidSignatureLength();
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) {
            revert InvalidSignature();
        }

        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != signer) {
            revert InvalidSignature();
        }
    }

    function splitSignature(bytes calldata signature)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        if (signature.length != 65) {
            revert InvalidSignatureLength();
        }

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
    }
}
