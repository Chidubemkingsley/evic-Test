# ARES Protocol Treasury Architecture

## System Architecture

The ARES Protocol treasury is a protocol that manage $500M+ in assets with multiple independent layers of defense and it distribute capital to contributors, liquidity providers and governance participants. The architecture touches  five different modules, each of them serving their purpose and have security boundaries and checks.

## Module Separation

### 1. ProposalModule.sol

The work of this ProposalModule is just to handle proposals of treasury action including commit-then-reveal event. Its main decisions:

- **Having Its Action Types structured**: Every requests are given label specifically(0 equals transfer, 1 equals call, 2 equals upgrade) so that it should know what to do to prevent a hacker from tricking the treasury contract from running a harmful upgrade on it
- **Approval Threshold**: Before any execution is performed or noted more than one of the owners must sign it off 
- **Fixing Deadline**: Proposals made by user must expire as it is meant to do so to prevent using expired proposals again.
- **Commit Phase**: A mandatory delay between queuing and execution prevents flash decisions

### 2. TimelockModule.sol

The TimelockModule provides the following guarantees:

- **Min/Max Delay Bounds**: Transactions must wait between 1-30 days
- **Grace Period**: Execution window of 14 days after delay completes
- **Queue Management**: Each transaction uses a unique nonce to prevent hash collisions
- **Executor Authorization**: Only authorized addresses can queue/execute

### 3. RewardDistributor.sol

Scalable token distribution using Merkle proofs:

- **Merkle Tree Verification**: O(log n) proof verification for thousands of recipients
- **Dual Claim Methods**: Supports both Merkle proofs and governor-signed claims
- **One-Time Claims**: Prevents double-claiming through recipient tracking
- **Fixing Deadline**: As it stands that before any deadline occurs claim must be submitted


### 4. GovernanceAttackPrevention.sol

Explicit defenses against economic attacks:

- **Cooldown Periods**: 1-day minimum between proposals per governance entity
- **Rate Limiting**: Maximum 5 proposals per 7-day window
- **Quorum Requirements**: Minimum 3 approvals for any proposal
- **Vote Locking**: Voters can lock votes for 5 days to prevent flash-loan voting
- **Discovering Large Transfer**: Any transfer that is above what it is expected must stop and not continue.

### 5. ARESTreasury.sol

The central coordinator that integrates all modules:

- **Module Composition**: Holds references to all other modules
- **Large Transfer Gates**: Additional checks for oversized withdrawals
- **Dual Execution Paths**: Direct execution for small amounts, queued for large
- **Initialization Guard**: Prevents re-initialization attacks

## Security Boundaries

### Trust Model

- **Governor**: Can propose and approve actions but cannot execute directly
- **Timelock**: Controls actual fund movement with mandatory delays
- **ProposalModule**: Verifies signatures and approval thresholds
- **RewardDistributor**: Independent claim system with Merkle verification

### Isolation Properties

1. **Signature Layer**: EIP-712 typed data signatures are verified in ProposalModule, independent of execution
2. **Queue Layer**: Transactions sit in TimelockModule queue, invisible to other modules until execution
3. **Distribution Layer**: Completely separate from treasury execution, operates on different token allocations
4. **Attack Prevention**: Runs parallel checks without blocking legitimate transactions




Here's the reorganized content grouped under **Trust Assumptions**:

---

## Trust Assumptions

### EIP-712 for Signature Security
EIP-712 provides domain-separated signatures that prevent cross-protocol replay (different domain hash), cross-chain replay (chain ID in domain).

**Trust assumption:** Signers are trusted to verify the domain they're signing for. The protocol assumes wallets correctly display EIP-712 structured data to users — if a wallet silently misrepresents the payload, the user could unknowingly sign a malicious message.

---

### Merkle Proofs for Reward Distribution
Linear storage of claims would cost O(n) gas per claim. Merkle proofs enable thousands of recipients without excessive gas costs.

**Trust assumption:** The Merkle root itself is trusted. The protocol assumes the off-chain root generation process is correct and that the governor who submits the root is not compromised. A malformed or malicious root cannot be detected on-chain.

---

### Modular Design for Isolation
Monolithic contracts create conditions where a single vulnerability destroys everything. Modular design ensures an attack on one module doesn't directly access funds, allows different security assumptions per operation, and makes individual components easier to audit and test.

**Trust assumption:** Module boundaries are trusted to hold. The design assumes inter-module calls behave as expected — if a module is upgraded to a malicious implementation, the isolation guarantee breaks down. Users must trust the upgrade governance process.

---