// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../modules/ProposalModule.sol";
import "../modules/TimelockModule.sol";
import "../modules/RewardDistributor.sol";
import "../modules/GovernanceAttackPrevention.sol";
import "../interfaces/ITreasury.sol";
import "../libraries/ReentrancyGuard.sol";

contract ARESTreasury is ITreasury, ReentrancyGuard {

    ProposalModule public proposalModule;
    TimelockModule public timelockModule;
    RewardDistributor public rewardDistributor;
    GovernanceAttackPrevention public attackPrevention;

    address public governor;
    address public pendingGovernor;

    mapping(address => uint256) public tokenBalances;

    uint256 public largeTransferThreshold;
    uint256 public proposalExecutionWindow;

    bool public initialized;

    event TreasuryInitialized(
        address proposalModule,
        address timelockModule,
        address rewardDistributor,
        address attackPrevention
    );

    error NotGovernor();
    error NotPendingGovernor();
    error LargeTransfer();
    error ExecutionWindowClosed();
    error ProposalNotReady();
    error NotInitialized();

    modifier onlyGovernor() {
        if (msg.sender != governor) {
            revert NotGovernor();
        }
        _;
    }

    modifier onlyInitialized() {
        if (!initialized) {
            revert NotInitialized();
        }
        _;
    }

    constructor(address _governor) {
        governor = _governor;
        ReentrancyGuard.init();
    }

    function initialize(
        address payable _proposalModule,
        address payable _timelockModule,
        address payable _rewardDistributor,
        address payable _attackPrevention,
        uint256 _largeTransferThreshold,
        uint256 _proposalExecutionWindow
    ) external onlyGovernor {
        require(!initialized, "Already initialized");

        proposalModule = ProposalModule(_proposalModule);
        timelockModule = TimelockModule(_timelockModule);
        rewardDistributor = RewardDistributor(_rewardDistributor);
        attackPrevention = GovernanceAttackPrevention(_attackPrevention);

        largeTransferThreshold = _largeTransferThreshold;
        proposalExecutionWindow = _proposalExecutionWindow;
        initialized = true;

        emit TreasuryInitialized(
            _proposalModule,
            _timelockModule,
            _rewardDistributor,
            _attackPrevention
        );
    }

    function execute(Action[] calldata actions) external payable onlyInitialized onlyGovernor nonReentrant {
        if (actions.length == 0) {
            revert ZeroActions();
        }

        for (uint256 i = 0; i < actions.length; ) {
            Action memory action = actions[i];

            if (action.actionType == 0) {
                if (action.amount >= largeTransferThreshold) {
                    if (!attackPrevention.checkLargeTransfer(action.amount)) {
                        revert LargeTransfer();
                    }
                }
                _executeTransfer(action.token, action.recipient, action.amount);
            } else if (action.actionType == 1) {
                _executeCall(action.recipient, action.amount, action.data);
            } else if (action.actionType == 2) {
                _executeUpgrade(action.recipient, action.data);
            }

            unchecked {
                ++i;
            }
        }

        emit FundsWithdrawn(address(0), msg.sender, msg.value);
    }

    function queueAndExecute(
        Action[] calldata actions,
        uint256 deadline,
        bytes calldata signatures
    ) external onlyInitialized onlyGovernor returns (uint256) {
        uint256 proposalId = proposalModule.createProposal(actions, deadline, signatures);

        attackPrevention.recordProposal(msg.sender);

        proposalModule.queueProposal(proposalId);

        proposalModule.executeProposal(proposalId);

        return proposalId;
    }

    function deposit(address token, uint256 amount) external payable onlyInitialized {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (token == address(0)) {
            tokenBalances[address(0)] += msg.value;
        } else {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
            tokenBalances[token] += amount;
        }

        emit FundsDeposited(token, msg.sender, amount);
    }

    function withdraw(
        address token,
        address recipient,
        uint256 amount
    ) external onlyInitialized onlyGovernor nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (amount >= largeTransferThreshold) {
            revert LargeTransfer();
        }

        if (token == address(0)) {
            tokenBalances[address(0)] -= amount;
            payable(recipient).transfer(amount);
        } else {
            tokenBalances[token] -= amount;
            IERC20(token).transfer(recipient, amount);
        }

        emit FundsWithdrawn(token, recipient, amount);
    }

    function withdrawLarge(
        address token,
        address recipient,
        uint256 amount,
        bytes calldata signatures
    ) external onlyInitialized onlyGovernor nonReentrant {
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            actionType: 0,
            token: token,
            recipient: recipient,
            amount: amount,
            data: ""
        });

        this.queueAndExecute(actions, block.timestamp + 2 days, signatures);
    }

    function setGovernor(address newGovernor) external onlyGovernor {
        pendingGovernor = newGovernor;
    }

    function acceptGovernor() external {
        if (msg.sender != pendingGovernor) {
            revert NotPendingGovernor();
        }
        governor = pendingGovernor;
        pendingGovernor = address(0);
        emit GovernanceUpdated(governor, true);
    }

    function setLargeTransferThreshold(uint256 newThreshold) external onlyGovernor {
        largeTransferThreshold = newThreshold;
    }

    function _executeTransfer(address token, address recipient, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (token == address(0)) {
            tokenBalances[address(0)] -= amount;
            payable(recipient).transfer(amount);
        } else {
            tokenBalances[token] -= amount;
            IERC20(token).transfer(recipient, amount);
        }
    }

    function _executeCall(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
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

    function getBalance(address token) external view returns (uint256) {
        return tokenBalances[token];
    }

    receive() external payable {
        tokenBalances[address(0)] += msg.value;
        emit FundsDeposited(address(0), msg.sender, msg.value);
    }

    error ZeroActions();
    error ZeroAmount();
}
