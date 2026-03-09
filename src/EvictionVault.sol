// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./access/Ownable.sol";
import {Pausable} from "./access/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract EvictionVault is Ownable, Pausable {

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
        uint256 submissionTime;
        uint256 executionTime;
    }

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public threshold;
    
    mapping(uint256 => mapping(address => bool)) public confirmed;
    mapping(uint256 => Transaction) public transactions;
    uint256 public txCount;
    
    mapping(address => uint256) public balances;
    bytes32 public merkleRoot;
    
    mapping(address => bool) public claimed;
    mapping(bytes32 => bool) public usedHashes;
    
    uint256 public constant TIMELOCK_DURATION = 1 hours;
    uint256 public totalVaultValue;

    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);
    event Submission(uint256 indexed txId);
    event Confirmation(uint256 indexed txId, address indexed owner);
    event Execution(uint256 indexed txId);
    event MerkleRootSet(bytes32 indexed newRoot);
    event Claim(address indexed claimant, uint256 amount);
    event OwnerAdded(address indexed newOwner);
    event OwnerRemoved(address indexed removedOwner);

    error ZeroAddress();
    error NotAnOwner();
    error InvalidThreshold();
    error AlreadyConfirmed();
    error AlreadyExecuted();
    error InsufficientConfirmations();
    error TimelockNotPassed();
    error AlreadyClaimed();
    error InvalidMerkleProof();
    error InsufficientBalance();
    error TransactionNotExecuted();

    constructor(address initialOwner, address[] memory _owners, uint256 _threshold) 
        Pausable(initialOwner) 
    {
        require(_owners.length > 0, "no owners");
        require(_threshold > 0 && _threshold <= _owners.length, "invalid threshold");

        threshold = _threshold;

        for (uint i = 0; i < _owners.length; i++) {
            address o = _owners[i];
            if (o == address(0)) {
                revert ZeroAddress();
            }
            isOwner[o] = true;
            owners.push(o);
        }
    }

    receive() external payable whenNotPaused {
        balances[msg.sender] += msg.value;
        totalVaultValue += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function deposit() external payable whenNotPaused {
        balances[msg.sender] += msg.value;
        totalVaultValue += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external whenNotPaused {
        if (balances[msg.sender] < amount) {
            revert InsufficientBalance();
        }

        balances[msg.sender] -= amount;
        totalVaultValue -= amount;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        emit Withdrawal(msg.sender, amount);
    }

    function submitTransaction(address to, uint256 value, bytes calldata data) 
        external 
        whenNotPaused 
    {
        if (!isOwner[msg.sender]) {
            revert NotAnOwner();
        }
        if (to == address(0)) {
            revert ZeroAddress();
        }

        uint256 id = txCount++;
        transactions[id] = Transaction({
            to: to,
            value: value,
            data: data,
            executed: false,
            confirmations: 1,
            submissionTime: block.timestamp,
            executionTime: 0
        });

        confirmed[id][msg.sender] = true;
        emit Submission(id);
    }

    function confirmTransaction(uint256 txId) external whenNotPaused {
        if (!isOwner[msg.sender]) {
            revert NotAnOwner();
        }

        Transaction storage txn = transactions[txId];
        
        if (txn.executed) {
            revert AlreadyExecuted();
        }
        if (confirmed[txId][msg.sender]) {
            revert AlreadyConfirmed();
        }

        confirmed[txId][msg.sender] = true;
        txn.confirmations++;

        if (txn.confirmations == threshold && txn.executionTime == 0) {
            txn.executionTime = block.timestamp + TIMELOCK_DURATION;
        }

        emit Confirmation(txId, msg.sender);
    }

    function executeTransaction(uint256 txId) external whenNotPaused {
        Transaction storage txn = transactions[txId];

        if (txn.confirmations < threshold) {
            revert InsufficientConfirmations();
        }
        if (txn.executed) {
            revert AlreadyExecuted();
        }
        if (block.timestamp < txn.executionTime) {
            revert TimelockNotPassed();
        }

        txn.executed = true;

        (bool success,) = txn.to.call{value: txn.value}(txn.data);
        require(success, "execution failed");

        emit Execution(txId);
    }

    function setMerkleRoot(bytes32 root) external onlyOwner {
        merkleRoot = root;
        emit MerkleRootSet(root);
    }

    function claim(bytes32[] calldata proof, uint256 amount) external whenNotPaused {
        if (claimed[msg.sender]) {
            revert AlreadyClaimed();
        }

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        bytes32 computedHash = MerkleProof.processProof(proof, leaf);

        if (computedHash != merkleRoot) {
            revert InvalidMerkleProof();
        }

        claimed[msg.sender] = true;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        totalVaultValue -= amount;

        emit Claim(msg.sender, amount);
    }

    function verifySignature(
        address signer,
        bytes32 messageHash,
        bytes memory signature
    ) external pure returns (bool) {
        return ECDSA.recover(messageHash, signature) == signer;
    }

    function emergencyWithdrawAll() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "transfer failed");
        
        totalVaultValue = 0;
    }

    function addOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }
        if (isOwner[newOwner]) {
            revert NotAnOwner();
        }
        
        isOwner[newOwner] = true;
        owners.push(newOwner);
        
        emit OwnerAdded(newOwner);
    }

    function removeOwner(address ownerToRemove) external onlyOwner {
        if (!isOwner[ownerToRemove]) {
            revert NotAnOwner();
        }
        if (owners.length <= 1) {
            revert InvalidThreshold();
        }
        
        isOwner[ownerToRemove] = false;
        
        emit OwnerRemoved(ownerToRemove);
    }

    function updateThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold == 0 || newThreshold > owners.length) {
            revert InvalidThreshold();
        }
        threshold = newThreshold;
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getTransaction(uint256 txId) external view returns (Transaction memory) {
        return transactions[txId];
    }

    function isConfirmed(uint256 txId, address owner) external view returns (bool) {
        return confirmed[txId][owner];
    }
}
