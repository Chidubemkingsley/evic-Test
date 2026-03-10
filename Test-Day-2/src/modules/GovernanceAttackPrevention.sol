// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/ReentrancyGuard.sol";

contract GovernanceAttackPrevention is ReentrancyGuard {

    struct QuorumState {
        uint256 currentQuorum;
        uint256 snapshotBlock;
        uint256 totalSupplySnapshot;
    }

    uint256 public quorumThreshold;
    uint256 public proposalCooldown;
    uint256 public largeTransferThreshold;
    uint256 public maxProposalsPerWindow;
    uint256 public timeWindow;

    mapping(address => uint256) public lastProposalTimestamp;
    mapping(address => uint256) public proposalCounts;
    mapping(bytes32 => bool) public executedProposals;
    mapping(address => uint256) public voterWeight;
    mapping(address => uint256) public voteLockEnd;

    address[] public governanceTokens;
    mapping(address => bool) public isGovernanceToken;

    uint256 public constant COOLDOWN_PERIOD = 1 days;
    uint256 public constant VOTE_LOCK_DURATION = 5 days;

    event QuorumUpdated(uint256 newQuorum);
    event LargeTransferDetected(address indexed token, uint256 amount);
    event GovernanceTokenRegistered(address indexed token);
    event VoteLocked(address indexed voter, uint256 lockEnd);

    error QuorumNotReached();
    error CooldownNotElapsed();
    error ProposalWindowExceeded();
    error LargeTransferBlocked();
    error VotesAreLocked();
    error InvalidQuorum();
    error InvalidCooldown();

    modifier noVoteLock() {
        if (block.timestamp < voteLockEnd[msg.sender]) {
            revert VotesAreLocked();
        }
        _;
    }

    modifier checkCooldown(address proposer) {
        if (block.timestamp < lastProposalTimestamp[proposer] + proposalCooldown) {
            revert CooldownNotElapsed();
        }
        _;
    }

    modifier checkProposalLimit(address proposer) {
        _updateProposalCount(proposer);
        if (proposalCounts[proposer] >= maxProposalsPerWindow) {
            revert ProposalWindowExceeded();
        }
        _;
    }

    constructor(
        uint256 _quorumThreshold,
        uint256 _proposalCooldown,
        uint256 _largeTransferThreshold,
        uint256 _maxProposalsPerWindow,
        uint256 _timeWindow
    ) {
        if (_quorumThreshold == 0) {
            revert InvalidQuorum();
        }
        if (_proposalCooldown < COOLDOWN_PERIOD) {
            revert InvalidCooldown();
        }

        quorumThreshold = _quorumThreshold;
        proposalCooldown = _proposalCooldown;
        largeTransferThreshold = _largeTransferThreshold;
        maxProposalsPerWindow = _maxProposalsPerWindow;
        timeWindow = _timeWindow;

        ReentrancyGuard.init();
    }

    function registerGovernanceToken(address token) external {
        require(token != address(0), "Invalid token");
        isGovernanceToken[token] = true;
        governanceTokens.push(token);
        emit GovernanceTokenRegistered(token);
    }

    function checkLargeTransfer(uint256 amount) external view returns (bool) {
        return amount >= largeTransferThreshold;
    }

    function recordProposal(address proposer) external checkCooldown(proposer) checkProposalLimit(proposer) {
        lastProposalTimestamp[proposer] = block.timestamp;
        proposalCounts[proposer]++;
    }

    function lockVotes(address voter, uint256 weight) external {
        if (weight > 0) {
            voteLockEnd[voter] = block.timestamp + VOTE_LOCK_DURATION;
            voterWeight[voter] = weight;
            emit VoteLocked(voter, voteLockEnd[voter]);
        }
    }

    function verifyQuorum(uint256 approvalCount) external view {
        if (approvalCount < quorumThreshold) {
            revert QuorumNotReached();
        }
    }

    function _updateProposalCount(address proposer) internal {
        if (block.timestamp > lastProposalTimestamp[proposer] + timeWindow) {
            proposalCounts[proposer] = 0;
        }
    }

    function setQuorumThreshold(uint256 newQuorum) external {
        require(newQuorum > 0, "Invalid quorum");
        quorumThreshold = newQuorum;
        emit QuorumUpdated(newQuorum);
    }

    function setLargeTransferThreshold(uint256 newThreshold) external {
        largeTransferThreshold = newThreshold;
    }

    function setCooldown(uint256 newCooldown) external {
        require(newCooldown >= COOLDOWN_PERIOD, "Cooldown too short");
        proposalCooldown = newCooldown;
    }

    function getGovernanceTokens() external view returns (address[] memory) {
        return governanceTokens;
    }
}
