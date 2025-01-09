// SPDX-License-Identifier: BUSL-1.1
// Central Limit Order Book (CLOB) exchange
// (c) Long Gamma Labs, 2023.
pragma solidity ^0.8.27;


struct Hop {
  uint64 params;
  uint32[] inputHopParams;
  address routerAddress;
  address fromToken;
  address toToken;
}


interface IRouter {
  function swapEthForTokens(
    uint256 amountOutMin,
    Hop[] calldata hops,
    address to,
    uint256 deadline
  ) external payable returns (uint256[] memory amounts);

  function swapTokensForEth(
    uint256 amountIn,
    uint256 amountOutMin,
    Hop[] calldata hops,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);

  function swapTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    Hop[] calldata hops,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);
}
