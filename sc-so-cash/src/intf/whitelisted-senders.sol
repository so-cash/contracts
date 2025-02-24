// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IWhitelistedSendersInternal {
    event Whitelisted(address indexed account, bool status);
}

interface IWhitelistedSenders is IWhitelistedSendersInternal {
    function isWhitelisted(address sender) external view returns (bool);
    function whitelist(address newSender) external;
    function blacklist(address oldSender) external;
}

interface IOwnable {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() external view returns (address);

    function transferOwnership(address account) external;
    function renounceOwnership() external;
}