// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockBlacklister {
    error Blacklisted();

    mapping(address => bool) public blacklisted;

    function blacklistUser(address user) external {
        blacklisted[user] = true;
    }

    function unblacklistUser(address user) external {
        blacklisted[user] = false;
    }

    function nonBlacklisted(address user) external view {
        if (blacklisted[user]) revert Blacklisted();
    }
}