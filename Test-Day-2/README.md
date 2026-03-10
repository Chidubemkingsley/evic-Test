# ARES Protocol Treasury

A secure treasury execution system for the ARES Protocol with modular architecture and defense-in-depth security.

## System Components

### Core Modules

1. **ProposalModule** (`src/modules/ProposalModule.sol`)
   - Multi-sig proposal creation with EIP-712 signatures
   - Approval threshold enforcement
   - Commit phase with mandatory delays

2. **TimelockModule** (`src/modules/TimelockModule.sol`)
   - Time-delayed execution (1-30 days)
   - Queue-based transaction management
   - Grace period enforcement

3. **RewardDistributor** (`src/modules/RewardDistributor.sol`)
   - Scalable Merkle proof-based claims
   - One-time claim enforcement
   - Signature-based claims option

4. **GovernanceAttackPrevention** (`src/modules/GovernanceAttackPrevention.sol`)
   - Proposal cooldown periods
   - Rate limiting
   - Quorum requirements
   - Vote locking

5. **ARESTreasury** (`src/core/ARESTreasury.sol`)
   - Central coordinator
   - Large transfer gates
   - Module integration

## Project Structure

```
src/
├── core/
│   └── ARESTreasury.sol
├── interfaces/
│   └── ITreasury.sol
├── libraries/
│   ├── EIP712.sol
│   ├── MerkleProof.sol
│   ├── ReentrancyGuard.sol
│   └── SignatureVerification.sol
└── modules/
    ├── GovernanceAttackPrevention.sol
    ├── ProposalModule.sol
    ├── RewardDistributor.sol
    └── TimelockModule.sol
```

## Deployed Contracts On Sepolia Ethereum Testnet

```
  Mock ARES Token: 0xD58B2390f141896f504BF867371940558d63c4E4
  GovernanceAttackPrevention: 0x4726a021ec380a755EBE883BEb800A5d06723E41
  TimelockModule: 0xA9aEe7ccA362Be628cfee1d2c5B1800E55580ff8
  ProposalModule: 0xA97c943555E92b7E8472118A3b058e72edcDC694
  RewardDistributor: 0x0A2AB73CB8311aFD261Ab92137ff70E9Ca268d69
  ARESTreasury: 0x05d75D2CC6C7750D14a9bfa1eEb7ECaa3F90e889
```


## Security Features

- **Reentrancy Protection**: Custom ReentrancyGuard on all state-changing functions
- **Signature Security**: EIP-712 typed data with domain separation
- **Replay Protection**: Per-user nonces, chain ID binding
- **Timelock**: Mandatory delays with execution windows
- **Large Transfer Controls**: Threshold-based gating
- **Governance Rate Limiting**: Cooldowns and proposal caps
- **Flash Loan Defense**: Vote locking mechanism

## Building

```bash
forge install
forge build
```

## Testing

```bash
forge test
```

## Deployment

At Your Root Project:
```
touch .env
```
Your Deployment Details.
```
RPC_URL=https://eth-sepolia.g.alchemy.com

PRIVATE_KEY=;

ETHERSCAN_API_KEY=;
```


```bash
forge script script/Deploy.s.sol --account deployer --broadcast --rpc-url https://sepolia.drpc.org
```

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Security Analysis](SECURITY.md)
