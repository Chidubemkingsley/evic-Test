// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEvictionVault {
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
        uint256 submissionTime;
        uint256 executionTime;
    }

    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);
    event Submission(uint256 indexed txId);
    event Confirmation(uint256 indexed txId, address indexed owner);
    event Execution(uint256 indexed txId);
    event MerkleRootSet(bytes32 indexed newRoot);
    event Claim(address indexed claimant, uint256 amount);

    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function submitTransaction(address to, uint256 value, bytes calldata data) external;
    function confirmTransaction(uint256 txId) external;
    function executeTransaction(uint256 txId) external;
    function setMerkleRoot(bytes32 root) external;
    function claim(bytes32[] calldata proof, uint256 amount) external;
    function emergencyWithdrawAll() external;
}
