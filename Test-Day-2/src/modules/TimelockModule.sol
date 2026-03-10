// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ITreasury.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/SignatureVerification.sol";

contract TimelockModule is ITimelock, ReentrancyGuard {

    uint256 public minDelay;
    uint256 public maxDelay;
    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MAX_DURATION = 30 days;

    mapping(bytes32 => bool) public queuedTransactions;
    mapping(bytes32 => uint256) public executionTimestamps;
    mapping(bytes32 => uint256) public queuedNonce;
    mapping(address => bool) public executors;

    uint256 public nonce;
    address public governor;

    modifier onlyExecutor() {
        if (!executors[msg.sender] && msg.sender != governor) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyGovernor() {
        if (msg.sender != governor) {
            revert NotGovernor();
        }
        _;
    }

    error NotAuthorized();
    error NotGovernor();
    error DelayTooShort();
    error DelayTooLong();
    error TransactionNotQueued();
    error TransactionAlreadyQueued();
    error TransactionExpired();
    error ExecutionWindowNotOpen();
    error ExecutionWindowClosed();

    event ExecutorUpdated(address indexed executor, bool enabled);

    constructor(address _governor, uint256 _minDelay, uint256 _maxDelay) {
        if (_minDelay < 1 days) {
            revert DelayTooShort();
        }
        if (_maxDelay > MAX_DURATION) {
            revert DelayTooLong();
        }
        if (_minDelay > _maxDelay) {
            revert DelayTooShort();
        }

        governor = _governor;
        minDelay = _minDelay;
        maxDelay = _maxDelay;
        executors[_governor] = true;
        ReentrancyGuard.init();
    }

    function queueTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 delay
    ) external onlyExecutor returns (bytes32) {
        if (delay < minDelay) {
            revert DelayTooShort();
        }
        if (delay > maxDelay) {
            revert DelayTooLong();
        }

        uint256 usedNonce = nonce;
        bytes32 txHash = keccak256(abi.encode(target, value, data, usedNonce));
        nonce++;

        if (queuedTransactions[txHash]) {
            revert TransactionAlreadyQueued();
        }

        uint256 executionTime = block.timestamp + delay;

        if (executionTime > block.timestamp + maxDelay + GRACE_PERIOD) {
            revert DelayTooLong();
        }

        queuedTransactions[txHash] = true;
        executionTimestamps[txHash] = executionTime;
        queuedNonce[txHash] = usedNonce;

        emit TransactionQueued(txHash, target, value, data, executionTime);

        return txHash;
    }

    function executeTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        bytes calldata signature
    ) external payable onlyExecutor nonReentrant returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, data, nonce));
        uint256 usedNonce = queuedNonce[txHash];

        bytes32 executionHash = keccak256(abi.encode(target, value, data, usedNonce));

        if (!queuedTransactions[executionHash]) {
            revert TransactionNotQueued();
        }

        uint256 executionTime = executionTimestamps[executionHash];

        if (block.timestamp < executionTime) {
            revert ExecutionWindowNotOpen();
        }
        if (block.timestamp > executionTime + GRACE_PERIOD) {
            revert TransactionExpired();
        }

        queuedTransactions[executionHash] = false;

        bytes memory result;
        if (data.length > 0) {
            (bool success, bytes memory returnData) = target.call{value: value}(data);
            result = returnData;

            if (!success) {
                if (returnData.length > 0) {
                    assembly {
                        let returndataSize := mload(returnData)
                        revert(add(32, returnData), returndataSize)
                    }
                }
                revert("Transaction execution failed");
            }
        } else {
            (bool success, ) = target.call{value: value}("");
            if (!success) {
                revert("Transaction execution failed");
            }
        }

        emit TransactionExecuted(txHash, target, value, data);

        return result;
    }

    function cancelTransaction(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyExecutor {
        bytes32 txHash = keccak256(abi.encode(target, value, data, nonce));

        if (!queuedTransactions[txHash]) {
            revert TransactionNotQueued();
        }

        queuedTransactions[txHash] = false;
        executionTimestamps[txHash] = 0;

        emit TransactionCancelled(txHash);
    }

    function setExecutor(address executor, bool enabled) external onlyGovernor {
        executors[executor] = enabled;
        emit ExecutorUpdated(executor, enabled);
    }

    function setGovernor(address newGovernor) external onlyGovernor {
        governor = newGovernor;
        executors[newGovernor] = true;
    }

    function setDelay(uint256 newDelay) external onlyGovernor {
        if (newDelay < 1 days) {
            revert DelayTooShort();
        }
        if (newDelay > MAX_DURATION) {
            revert DelayTooLong();
        }
        if (newDelay < minDelay) {
            revert DelayTooShort();
        }
        if (newDelay > maxDelay) {
            revert DelayTooLong();
        }

        minDelay = newDelay;
    }

    function getMinDelay() external view returns (uint256) {
        return minDelay;
    }

    function getMaxDelay() external view returns (uint256) {
        return maxDelay;
    }

    function isQueued(bytes32 txHash) external view returns (bool) {
        return queuedTransactions[txHash];
    }

    receive() external payable {}
}
