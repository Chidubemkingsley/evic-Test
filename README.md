# EvictionVault - Security Hardened Smart Contract

## Overview

This is a refactored, modular version of the EvictionVault smart contract with critical security vulnerabilities addressed. The original monolithic contract has been decomposed into a secure, multi-file architecture.

## Project Structure

```
src/
├── access/
│   ├── Ownable.sol         # Ownable access control
│   └── Pausable.sol        # Pausable functionality
├── governance/
│   └── TimelockController.sol  # Timelock governance
├── interfaces/
│   └── IEvictionVault.sol  # Interface definition
└── EvictionVault.sol       # Main vault contract
```

## Security Fixes Implemented

### 1. setMerkleRoot Callable by Anyone
**Vulnerability:** The `setMerkleRoot` function had no access control, allowing anyone to change the merkle root.

**Fix:** Added `onlyOwner` modifier to restrict access to the contract owner only.

```solidity
function setMerkleRoot(bytes32 root) external onlyOwner {
    merkleRoot = root;
    emit MerkleRootSet(root);
}
```

### 2. emergencyWithdrawAll Public Drain
**Vulnerability:** Anyone could call `emergencyWithdrawAll` and drain all funds from the vault.

**Fix:** Added `onlyOwner` modifier to ensure only the owner can emergency withdraw funds.

```solidity
function emergencyWithdrawAll() external onlyOwner {
    uint256 balance = address(this).balance;
    (bool success,) = msg.sender.call{value: balance}("");
    require(success, "transfer failed");
    totalVaultValue = 0;
}
```

### 3. pause/unpause Single Owner Control
**Vulnerability:** Pause/unpause was accessible by any "owner" in the multi-sig sense, allowing unilateral pausing by any signer.

**Fix:** In access/Pausable.sol-- Changed to use `onlyOwner` modifier, where the owner is a separate role from transaction signers. This provides proper separation of concerns between contract administration and transaction execution.

```solidity
function pause() public onlyOwner whenNotPaused {
    _paused = true;
    emit Paused(msg.sender);
}
```

### 4. receive() Uses tx.origin
**Vulnerability:** The `receive()` function used `tx.origin` which is vulnerable to phishing attacks.

**Fix:** Changed to use `msg.sender` instead, which is the secure approach.

```solidity
receive() external payable whenNotPaused {
    balances[msg.sender] += msg.value;
    totalVaultValue += msg.value;
    emit Deposit(msg.sender, msg.value);
}
```

### 5. withdraw & claim Uses .transfer
**Vulnerability:** Using `.transfer()` is deprecated due to gas forwarding issues and can cause transactions to fail.

**Fix:** Replaced `.transfer()` with `.call()` which is the recommended approach.

```solidity
(bool success,) = msg.sender.call{value: amount}("");
require(success, "transfer failed");
```

### 6. Timelock Execution
**Vulnerability:** The timelock could be set multiple times incorrectly.

**Fix:** Added proper checks to ensure execution time is only set once and proper validation:

```solidity
if (txn.confirmations == threshold && txn.executionTime == 0) {
    txn.executionTime = block.timestamp + TIMELOCK_DURATION;
}
```

## Building and Testing

### Install Dependencies
```bash
forge install
```

### Build
```bash
forge build
```

### Run Tests
```bash
forge test
```

### Run Tests with Verbose Output
```bash
forge test -vvv
```

## Test Results

All 9 positive tests pass successfully:

- `test_Deposit` - Tests deposit functionality
- `test_Receive` - Tests receive function
- `test_Withdraw` - Tests withdraw functionality
- `test_SetMerkleRoot` - Tests merkle root setting (owner-only)
- `test_EmergencyWithdrawAll` - Tests emergency withdrawal (owner-only)
- `test_PauseAndUnpause` - Tests pause/unpause functionality (owner-only)
- `test_SubmitTransaction` - Tests transaction submission
- `test_AddOwner` - Tests owner addition
- `test_OwnerManagement` - Tests owner management

## Contract Features

- **Multi-signature Support**: Multiple owners can submit and confirm transactions
- **Timelock**: Transactions require a timelock period before execution
- **Merkle Proof Claims**: Users can claim tokens via merkle proof verification
- **Pausable**: Contract can be paused by owner in emergencies
- **Emergency Withdrawal**: Owner can withdraw all funds in case of emergency
- **Deposit/Withdrawal**: Standard ERC-20-like balance management for ETH

## License

MIT
