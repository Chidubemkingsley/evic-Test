// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "../access/Ownable.sol";

abstract contract TimelockController is Ownable {
    uint256 private _delay;

    mapping(bytes32 => bool) public pendingCalls;

    event CallScheduled(bytes32 indexed id, uint256 indexed delay);
    event CallExecuted(bytes32 indexed id);

    error MinDelayTooLow();
    error InvalidDelay();
    error CallNotPending();
    error TimestampNotPassed();
    error TimestampNotReady();

    uint public constant MIN_DELAY = 1 hours;

    constructor(address initialOwner, uint256 delay_) Ownable(initialOwner) {
        if (delay_ < MIN_DELAY) {
            revert MinDelayTooLow();
        }
        _delay = delay_;
    }

    function delay() public view returns (uint256) {
        return _delay;
    }

    function hashCall(address to, uint256 value, bytes calldata data) public pure returns (bytes32) {
        return keccak256(abi.encode(to, value, data));
    }

    function scheduleCall(address to, uint256 value, bytes calldata data) public onlyOwner returns (bytes32 id) {
        id = hashCall(to, value, data);
        if (pendingCalls[id]) {
            revert CallNotPending();
        }
        pendingCalls[id] = true;
        emit CallScheduled(id, _delay);
    }

    function executeCall(bytes32 id, address to, uint256 value, bytes calldata data) public onlyOwner {
        if (!pendingCalls[id]) {
            revert CallNotPending();
        }
        bytes32 expectedHash = hashCall(to, value, data);
        if (id != expectedHash) {
            revert CallNotPending();
        }
        
        delete pendingCalls[id];
        
        (bool success,) = to.call{value: value}(data);
        require(success, "Call failed");
        
        emit CallExecuted(id);
    }

    function cancelCall(bytes32 id) public onlyOwner {
        if (!pendingCalls[id]) {
            revert CallNotPending();
        }
        delete pendingCalls[id];
    }
}
