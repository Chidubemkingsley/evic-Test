// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {EvictionVault} from "../src/EvictionVault.sol";

contract EvictionVaultTest is Test {
    EvictionVault public vault;
    
    address public owner = address(0x1);
    address[] public owners;
    uint256 public threshold = 2;
    
    address public user1 = address(0x10);
    address public user2 = address(0x20);
    address public user3 = address(0x30);

    function setUp() public {
        owners.push(user1);
        owners.push(user2);
        owners.push(user3);
        
        vault = new EvictionVault(owner, owners, threshold);
        
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    function test_Deposit() public {
        vm.startPrank(user1);
        
        uint256 balanceBefore = address(vault).balance;
        
        vault.deposit{value: 1 ether}();
        
        assertEq(vault.balances(user1), 1 ether);
        assertEq(address(vault).balance, balanceBefore + 1 ether);
        assertEq(vault.totalVaultValue(), 1 ether);
        
        vm.stopPrank();
    }

    function test_Receive() public {
        vm.startPrank(user1);
        
        uint256 balanceBefore = address(vault).balance;
        
        (bool success,) = address(vault).call{value: 1 ether}("");
        require(success);
        
        assertEq(vault.balances(user1), 1 ether);
        assertEq(address(vault).balance, balanceBefore + 1 ether);
        
        vm.stopPrank();
    }

    function test_Withdraw() public {
        vm.startPrank(user1);
        
        vault.deposit{value: 2 ether}();
        
        uint256 vaultBalanceBefore = address(vault).balance;
        uint256 userBalanceBefore = user1.balance;
        
        vault.withdraw(1 ether);
        
        assertEq(vault.balances(user1), 1 ether);
        assertEq(address(vault).balance, vaultBalanceBefore - 1 ether);
        assertEq(user1.balance, userBalanceBefore + 1 ether);
        
        vm.stopPrank();
    }

    function test_SetMerkleRoot() public {
        bytes32 newRoot = keccak256(abi.encodePacked("new merkle root"));
        
        vm.prank(owner);
        vault.setMerkleRoot(newRoot);
        
        assertEq(vault.merkleRoot(), newRoot);
    }

    function test_EmergencyWithdrawAll() public {
        vm.deal(address(vault), 10 ether);
        
        uint256 vaultBalance = address(vault).balance;
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.prank(owner);
        vault.emergencyWithdrawAll();
        
        assertEq(address(vault).balance, 0);
        assertEq(vault.totalVaultValue(), 0);
        assertEq(owner.balance, ownerBalanceBefore + vaultBalance);
    }

    function test_PauseAndUnpause() public {
        vm.prank(owner);
        vault.pause();
        
        assertTrue(vault.paused());
        
        vm.prank(owner);
        vault.unpause();
        
        assertFalse(vault.paused());
    }

    function test_SubmitTransaction() public {
        vm.startPrank(user1);
        
        bytes memory data = abi.encodeWithSignature("test()");
        vault.submitTransaction(address(0x123), 0, data);
        
        assertTrue(vault.isConfirmed(0, user1));
        
        vm.stopPrank();
    }

    function test_AddOwner() public {
        address newOwner = address(0x999);
        
        vm.prank(owner);
        vault.addOwner(newOwner);
        
        assertTrue(vault.isOwner(newOwner));
    }

    function test_OwnerManagement() public {
        assertTrue(vault.isOwner(user1));
        assertTrue(vault.isOwner(user2));
        assertTrue(vault.isOwner(user3));
        
        address[] memory vaultOwners = vault.getOwners();
        
        assertEq(vaultOwners.length, 3);
    }
}
