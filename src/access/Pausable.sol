// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "./Ownable.sol";

abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();

    constructor(address initialOwner) Ownable(initialOwner) {
        _paused = false;
    }

    modifier whenNotPaused() {
        if (paused()) {
            revert EnforcedPause();
        }
        _;
    }

    modifier whenPaused() {
        if (!paused()) {
            revert ExpectedPause();
        }
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function pause() public onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}
