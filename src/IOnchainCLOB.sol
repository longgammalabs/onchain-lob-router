// SPDX-License-Identifier: BUSL-1.1
// Central Limit Order Book (CLOB) exchange
// (c) Long Gamma Labs, 2023.
pragma solidity ^0.8.27;


interface IOnchainCLOB {
    function getConfig() external view returns (
        uint256 _scaling_factor_token_x,
        uint256 _scaling_factor_token_y,
        address _token_x,
        address _token_y,
        bool _supports_native_eth,
        bool _is_token_x_weth,
        address _ask_trie,
        address _bid_trie,
        uint64 _admin_commission_rate,
        uint64 _total_aggressive_commission_rate,
        uint64 _total_passive_commission_rate,
        uint64 _passive_order_payout_rate,
        bool _should_invoke_on_trade
    );

    receive() external payable;

    function placeOrder(
        bool isAsk,
        uint128 quantity,
        uint72 price,
        uint128 max_commission,
        bool market_only,
        bool post_only,
        bool transfer_executed_tokens,
        uint256 expires
    ) external payable returns (
        uint64 order_id,
        uint128 executed_shares,
        uint128 executed_value,
        uint128 aggressive_fee
    );

    function placeMarketOrderWithTargetValue(
        bool isAsk,
        uint128 target_token_y_value,
        uint72 price,
        uint128 max_commission,
        bool transfer_executed_tokens,
        uint256 expires
    ) external payable returns (
        uint128 executed_shares,
        uint128 executed_value,
        uint128 aggressive_fee
    );
}
