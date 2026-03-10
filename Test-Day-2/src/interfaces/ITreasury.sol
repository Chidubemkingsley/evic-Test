// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

struct Action {
    uint8 actionType;
    address token;
    address recipient;
    uint256 amount;
    bytes data;
}

interface IProposalModule {
    event ProposalCreated(uint256 indexed proposalId, address proposer, uint256 nonce);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event ProposalQueued(uint256 indexed proposalId, uint256 executionTime);

    struct Proposal {
        uint256 id;
        address proposer;
        bytes32 actionsHash;
        uint256 nonce;
        uint256 deadline;
        uint256 executionTime;
        bool executed;
        bool cancelled;
        bool queued;
        uint256 approvalCount;
    }

    function createProposal(Action[] calldata actions, uint256 deadline, bytes calldata signatures) external returns (uint256);
    function executeProposal(uint256 proposalId) external;
    function cancelProposal(uint256 proposalId) external;
    function queueProposal(uint256 proposalId) external;
    function getProposal(uint256 proposalId) external view returns (Proposal memory);
    function getNonce(address user) external view returns (uint256);
}

interface ITimelock {
    event TransactionQueued(
        bytes32 indexed txHash,
        address target,
        uint256 value,
        bytes data,
        uint256 executionTime
    );
    event TransactionExecuted(
        bytes32 indexed txHash,
        address target,
        uint256 value,
        bytes data
    );
    event TransactionCancelled(bytes32 indexed txHash);

    function queueTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 delay
    ) external returns (bytes32);

    function executeTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        bytes calldata signature
    ) external payable returns (bytes memory);

    function cancelTransaction(
        address target,
        uint256 value,
        bytes calldata data
    ) external;

    function getMinDelay() external view returns (uint256);
    function getMaxDelay() external view returns (uint256);
}

interface IRewardDistributor {
    event MerkleRootUpdated(bytes32 indexed merkleRoot);
    event Claimed(address indexed recipient, uint256 amount, uint256 nonce);

    function claim(
        address recipient,
        uint256 amount,
        uint256 nonce,
        bytes32[] calldata proof
    ) external;

    function updateMerkleRoot(bytes32 newRoot) external;

    function getMerkleRoot() external view returns (bytes32);
    function hasClaimed(address recipient) external view returns (bool);
    function getClaimedAmount(address recipient) external view returns (uint256);
}

interface ITreasury {
    event FundsDeposited(address indexed token, address indexed from, uint256 amount);
    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);
    event GovernanceUpdated(address indexed newGovernor, bool enabled);

    function execute(Action[] calldata actions) external payable;
    function deposit(address token, uint256 amount) external payable;
    function withdraw(address token, address recipient, uint256 amount) external;
}
