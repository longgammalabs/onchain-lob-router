// SPDX-License-Identifier: BUSL-1.1
// Central Limit Order Book (CLOB) exchange
// (c) Long Gamma Labs, 2023.
pragma solidity ^0.8.27;


interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
}
