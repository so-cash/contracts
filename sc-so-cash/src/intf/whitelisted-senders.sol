// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

/**
    * @title IWhitelistedSendersInternal interface 
    * @notice The whitelisted senders service emits events defined in this interface.
    * @dev This interface exposes the events of the whitelisted senders service.
 */
interface IWhitelistedSendersInternal {
    /**
        * @notice Emitted when a sender is whitelisted or blacklisted.
        * @dev The purpose of the whitelisting is context dependent.
        * @param account The address of the sender.
        * @param status The status of the sender: true is allowed, false otherwise.
     */
    event Whitelisted(address indexed account, bool status);
}

/**
    * @title IWhitelistedSenders interface for whitelisted senders
    * @notice The whitelisted senders service is used to manage the list of senders that are allowed to send transactions to the so|cash scope.
    <br>It is a facet to manage a list of allowed wallets for any kind of service, so it can be imported by other facet and this interface exposed.
    * @dev This interface is used to manage the list of senders that are allowed by other facet. 
    <br>This implementation does not do anything specifically other than enabling the setting of the allowed wallets.
    <br>Note that the implementation normally also implement [IOwnable](./api-IOwnable) to manage the owner of the whitelisting.
    <br>Inherit from [IWhitelistedSendersInternal](./api-IWhitelistedSendersInternal) to access the events.
 */
interface IWhitelistedSenders is IWhitelistedSendersInternal {
    /**
        * @notice Check if a sender is whitelisted.
        * @dev No control of caller is done in this function.
        * @param sender The address of the sender.
        * @return true if the sender is whitelisted or the owner, false otherwise.
     */
    function isWhitelisted(address sender) external view returns (bool);

    /**
        * @notice Whitelist a sender.
        * @dev Only an other whitelisted sender (or the owner) can whitelist a new sender.
        * @param newSender The address of the sender.
     */
    function whitelist(address newSender) external;

    /**
        * @notice Remove sender from the whitelist.
        * @dev Only an other whitelisted sender (or the owner, or the targetted sender) can blacklist a sender.
        * @param oldSender The address of the sender to remove.
     */
    function blacklist(address oldSender) external;
}


/**
    * @title IOwnable interface for ownership management
    * @notice Interface of the openzeppelin ownership management service.
    * @dev This interface is used by several smart contracts that need a owner to control the contract.
 */
interface IOwnable {

    /**
    * @notice Emitted when ownership is transferred.
    * @param previousOwner The address of the previous owner.
    * @param newOwner The address of the new owner.
     */
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
    * @notice Get the owner of the contract.
    * @return The address of the owner.
     */
    function owner() external view returns (address);

    /**
    * @notice Transfer ownership to a new account.
    * @dev Only the owner can transfer ownership.
    * @param account The address of the new owner.
     */
    function transferOwnership(address account) external;

    /**
    * @notice Renounce ownership.
    * @dev Only the owner can renounce ownership.
    <br>It will set the owner to the zero address.
    <br>Equivalent to `transferOwnership(address(0))`.
     */
    function renounceOwnership() external;
}