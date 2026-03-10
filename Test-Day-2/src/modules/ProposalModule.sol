// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ITreasury.sol";
import "../libraries/EIP712.sol";
import "../libraries/SignatureVerification.sol";
import "../libraries/ReentrancyGuard.sol";

contract ProposalModule is IProposalModule, ReentrancyGuard {

    uint256 private _proposalCount;
    uint256 public minApprovalThreshold;
    uint256 public proposalLifetime;
    uint256 public commitPhaseDuration;

    mapping(address => uint256) public nonces;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => Action[]) public proposalActions;
    mapping(uint256 => mapping(address => bool)) public hasApproved;

    address public governor;
    address public timelock;

    modifier onlyGovernor() {
        if (msg.sender != governor) {
            revert NotGovernor();
        }
        _;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) {
            revert NotTimelock();
        }
        _;
    }

    error NotGovernor();
    error NotTimelock();
    error InvalidDeadline();
    error ProposalAlreadyExecuted();
    error ProposalNotExecutable();
    error ProposalExpired();
    error AlreadyApproved();
    error InsufficientApprovals();
    error InvalidSignature();
    error ProposalNotQueued();
    error ExecutionWindowClosed();
    error ZeroActions();

    constructor(
        address _governor,
        address _timelock,
        uint256 _minApprovalThreshold,
        uint256 _proposalLifetime,
        uint256 _commitPhaseDuration
    ) {
        governor = _governor;
        timelock = _timelock;
        minApprovalThreshold = _minApprovalThreshold;
        proposalLifetime = _proposalLifetime;
        commitPhaseDuration = _commitPhaseDuration;
        ReentrancyGuard.init();
    }

    function createProposal(
        Action[] calldata actions,
        uint256 deadline,
        bytes calldata signatures
    ) external onlyGovernor returns (uint256) {
        if (actions.length == 0) {
            revert ZeroActions();
        }
        if (deadline <= block.timestamp) {
            revert InvalidDeadline();
        }
        if (deadline > block.timestamp + proposalLifetime) {
            revert InvalidDeadline();
        }

        uint256 nonce = nonces[msg.sender]++;

        bytes32 digest = EIP712.computeDigest(
            EIP712.hashProposal(nonce, deadline, actions)
        );

        SignatureVerification.verify(digest, signatures, msg.sender);

        uint256 proposalId = _proposalCount++;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            actionsHash: keccak256(abi.encode(actions)),
            nonce: nonce,
            deadline: deadline,
            executionTime: 0,
            executed: false,
            cancelled: false,
            queued: false,
            approvalCount: 1
        });

        Action[] storage proposalActionList = proposalActions[proposalId];
        for (uint256 i = 0; i < actions.length; i++) {
            proposalActionList.push(actions[i]);
        }

        hasApproved[proposalId][msg.sender] = true;

        emit ProposalCreated(proposalId, msg.sender, nonce);

        return proposalId;
    }

    function approveProposal(uint256 proposalId, bytes calldata signature) external onlyGovernor {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.executed) {
            revert ProposalAlreadyExecuted();
        }
        if (proposal.cancelled) {
            revert ProposalNotExecutable();
        }
        if (block.timestamp > proposal.deadline) {
            revert ProposalExpired();
        }
        if (hasApproved[proposalId][msg.sender]) {
            revert AlreadyApproved();
        }

        bytes32 digest = EIP712.computeDigest(
            keccak256(abi.encode(
                keccak256("Approve(uint256 proposalId,uint256 nonce,uint256 deadline)"),
                proposalId,
                proposal.nonce,
                proposal.deadline
            ))
        );

        SignatureVerification.verify(digest, signature, msg.sender);

        hasApproved[proposalId][msg.sender] = true;
        proposal.approvalCount++;
    }

    function queueProposal(uint256 proposalId) external onlyTimelock {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.executed) {
            revert ProposalAlreadyExecuted();
        }
        if (proposal.cancelled) {
            revert ProposalNotExecutable();
        }
        if (proposal.approvalCount < minApprovalThreshold) {
            revert InsufficientApprovals();
        }
        if (block.timestamp > proposal.deadline) {
            revert ProposalExpired();
        }

        proposal.executionTime = block.timestamp + commitPhaseDuration;
        proposal.queued = true;

        emit ProposalQueued(proposalId, proposal.executionTime);
    }

    function executeProposal(uint256 proposalId) external onlyTimelock nonReentrant {
        Proposal storage proposal = proposals[proposalId];

        if (!proposal.queued) {
            revert ProposalNotQueued();
        }
        if (proposal.executed) {
            revert ProposalAlreadyExecuted();
        }
        if (block.timestamp < proposal.executionTime) {
            revert ExecutionWindowClosed();
        }
        if (block.timestamp > proposal.deadline) {
            revert ProposalExpired();
        }

        proposal.executed = true;

        Action[] storage actions = proposalActions[proposalId];
        for (uint256 i = 0; i < actions.length; ) {
            _executeAction(actions[i]);
            unchecked {
                ++i;
            }
        }

        emit ProposalExecuted(proposalId);
    }

    function cancelProposal(uint256 proposalId) external onlyGovernor {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.executed) {
            revert ProposalAlreadyExecuted();
        }
        if (proposal.cancelled) {
            revert ProposalNotExecutable();
        }

        proposal.cancelled = true;

        emit ProposalCancelled(proposalId);
    }

    function _executeAction(Action memory action) internal {
        if (action.actionType == 0) {
            _executeTransfer(action.token, action.recipient, action.amount);
        } else if (action.actionType == 1) {
            _executeCall(action.recipient, action.data);
        } else if (action.actionType == 2) {
            _executeUpgrade(action.recipient, action.data);
        }
    }

    function _executeTransfer(address token, address recipient, uint256 amount) internal {
        if (token == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            IERC20(token).transfer(recipient, amount);
        }
    }

    function _executeCall(address target, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: 0}(data);
        if (!success) {
            if (result.length > 0) {
                assembly {
                    let returndataSize := mload(result)
                    revert(add(32, result), returndataSize)
                }
            }
            revert("Call failed");
        }
    }

    function _executeUpgrade(address target, bytes memory data) internal {
        (bool success, bytes memory result) = target.delegatecall(data);
        if (!success) {
            if (result.length > 0) {
                assembly {
                    let returndataSize := mload(result)
                    revert(add(32, result), returndataSize)
                }
            }
            revert("Upgrade failed");
        }
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getNonce(address user) external view returns (uint256) {
        return nonces[user];
    }

    function setGovernor(address newGovernor) external onlyGovernor {
        governor = newGovernor;
    }

    function setTimelock(address newTimelock) external onlyGovernor {
        timelock = newTimelock;
    }

    receive() external payable {}
}
