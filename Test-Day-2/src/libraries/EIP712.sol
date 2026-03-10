// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ITreasury.sol";

library EIP712 {
    bytes32 constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(uint256 nonce,uint256 deadline,Action[] actions)Action(uint8 actionType,address token,address recipient,uint256 amount,bytes data)"
    );

    bytes32 constant ACTION_TYPEHASH = keccak256(
        "Action(uint8 actionType,address token,address recipient,uint256 amount,bytes data)"
    );

    bytes32 constant CLAIM_TYPEHASH = keccak256(
        "Claim(address recipient,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    bytes32 constant CANCEL_TYPEHASH = keccak256(
        "Cancel(uint256 proposalId,uint256 nonce,uint256 deadline)"
    );

    function hashProposal(
        uint256 nonce,
        uint256 deadline,
        Action[] memory actions
    ) internal pure returns (bytes32) {
        bytes32[] memory actionHashes = new bytes32[](actions.length);
        for (uint256 i = 0; i < actions.length; i++) {
            actionHashes[i] = hashAction(actions[i]);
        }

        return keccak256(
            abi.encode(
                PROPOSAL_TYPEHASH,
                nonce,
                deadline,
                keccak256(abi.encodePacked(actionHashes))
            )
        );
    }

    function hashAction(Action memory action) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ACTION_TYPEHASH,
                action.actionType,
                action.token,
                action.recipient,
                action.amount,
                keccak256(action.data)
            )
        );
    }

    function hashClaim(
        address recipient,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                recipient,
                amount,
                nonce,
                deadline
            )
        );
    }

    function hashCancel(
        uint256 proposalId,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CANCEL_TYPEHASH,
                proposalId,
                nonce,
                deadline
            )
        );
    }

    function computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("ARES Protocol"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function computeDigest(bytes32 structHash) internal view returns (bytes32) {
        bytes32 domainSeparator = computeDomainSeparator();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
