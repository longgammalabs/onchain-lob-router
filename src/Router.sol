// SPDX-License-Identifier: BUSL-1.1
// Central Limit Order Book (CLOB) exchange
// (c) Long Gamma Labs, 2023.
pragma solidity ^0.8.27;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


import {IRouter, Hop} from "./IRouter.sol";
import {IOnchainCLOB} from "./IOnchainCLOB.sol";
import {IV2Router} from "./IV2Router.sol";
import {IV3Router} from "./IV3Router.sol";
import {IWETH} from "./IWETH.sol";
import {Errors} from "./Errors.sol";


contract Router is IRouter, ReentrancyGuard {
  using SafeERC20 for IERC20;

  uint8 constant UNWRAP_AND_WRAP_ID = 0;
  uint8 constant ONCHAINCLOB_ID = 1;
  uint8 constant V2_ROUTER_ID = 2;
  uint8 constant V3_ROUTER_ID = 3;

  struct SwapParams {
    uint256 amountIn;
    address routerAddress;
    address fromToken;
    address toToken;
    bool isFromNative;
    bool isToNative;
    uint24 poolV3fee;
    uint256 deadline;
  }

  receive() external payable {
  }

  function swapEthForTokens(
    uint256 amountOutMin,
    Hop[] calldata hops,
    address to,
    uint256 deadline
  ) external payable nonReentrant() returns (uint256[] memory amounts) {
    require(msg.value > 0, Errors.ZeroTokenTransferNotAllowed());
    require(hops.length > 0, Errors.WrongHopsCount());

    uint256[] memory amountRests;

    (amounts, amountRests) = _swap(
      msg.value,
      hops,
      deadline
    );

    // check final balances
    IERC20 toToken = IERC20(hops[hops.length - 1].toToken);

    uint256 finalAmountOut = toToken.balanceOf(address(this));
    require(finalAmountOut >= amountOutMin, Errors.InsufficientAmountOut());

    // withdraw tokens
    toToken.safeTransfer(to, finalAmountOut);

    // refund rests
    _refundRests(hops, amountRests);
  }

  function swapTokensForEth(
    uint256 amountIn,
    uint256 amountOutMin,
    Hop[] calldata hops,
    address to,
    uint256 deadline
  ) external nonReentrant() returns (uint256[] memory amounts) {
    require(amountIn > 0, Errors.ZeroTokenTransferNotAllowed());
    require(hops.length > 0, Errors.WrongHopsCount());

    IERC20 fromToken = IERC20(hops[0].fromToken);

    // deposit tokens
    _safeTansferFromWithBalanceCheck(
      fromToken,
      msg.sender,
      address(this),
      amountIn
    );

    uint256[] memory amountRests;

    (amounts, amountRests) = _swap(
      amountIn,
      hops,
      deadline
    );

    uint256 finalAmountOut = address(this).balance;
    require(finalAmountOut >= amountOutMin, Errors.InsufficientAmountOut());

    // withdraw result
    _sendETH(to, finalAmountOut);

    // refund rests
    _refundRests(hops, amountRests);
  }

  function swapTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    Hop[] calldata hops,
    address to,
    uint256 deadline
  ) external nonReentrant() returns (uint256[] memory amounts) {
    require(amountIn > 0, Errors.ZeroTokenTransferNotAllowed());
    require(hops.length > 0, Errors.WrongHopsCount());

    IERC20 fromToken = IERC20(hops[0].fromToken);

    // deposit tokens
    _safeTansferFromWithBalanceCheck(
      fromToken,
      msg.sender,
      address(this),
      amountIn
    );

    uint256[] memory amountRests;

    (amounts, amountRests) = _swap(
      amountIn,
      hops,
      deadline
    );

    // check final balances
    IERC20 toToken = IERC20(hops[hops.length - 1].toToken);

    uint256 finalAmountOut = toToken.balanceOf(address(this));
    require(finalAmountOut >= amountOutMin, Errors.InsufficientAmountOut());

    // withdraw tokens
    toToken.safeTransfer(to, finalAmountOut);

    // refund rests
    _refundRests(hops, amountRests);
  }

  function _swap(
    uint256 amountIn,
    Hop[] calldata hops,
    uint256 deadline
  ) internal returns (uint256[] memory hopsAmountOut, uint256[] memory hopsAmountOutRest) {
    hopsAmountOut = new uint256[](hops.length + 1);
    hopsAmountOut[0] = amountIn;

    hopsAmountOutRest = new uint256[](hops.length + 1);
    hopsAmountOutRest[0] = amountIn;

    // execute hops
    for (uint i = 0; i < hops.length; ++i) {
      uint hopId = i + 1;

      uint8 dexId;
      bool useForRest;
      SwapParams memory swapParams;

      (
        dexId,
        useForRest,
        swapParams.isFromNative,
        swapParams.isToNative,
        swapParams.poolV3fee
      ) = _unpackParams(hops[i].params);

      swapParams.routerAddress = hops[i].routerAddress;
      swapParams.fromToken = hops[i].fromToken;
      swapParams.toToken = hops[i].toToken;
      swapParams.amountIn = _calculateHopAmountIn(hops[i], hopsAmountOut, hopsAmountOutRest, useForRest);
      swapParams.deadline = deadline;

      uint256 hopFromTokenBalanceOld = _getBalance(swapParams.fromToken, swapParams.isFromNative);
      uint256 hopToTokenBalanceOld = _getBalance(swapParams.toToken, swapParams.isToNative);

      if (dexId == UNWRAP_AND_WRAP_ID) {
        _unwrapAndWrap(swapParams);
      } else if (dexId == ONCHAINCLOB_ID) {
        _swapUsingOnchainCLOB(swapParams);
      } else if (dexId == V2_ROUTER_ID) {
        _swapUsingV2Router(swapParams);
      } else if (dexId == V3_ROUTER_ID) {
        _swapUsingV3Router(swapParams);
      } else {
        revert Errors.UnsupportedDex();
      }

      uint256 hopFromTokenBalanceNew = _getBalance(swapParams.fromToken, swapParams.isFromNative);
      uint256 hopToTokenBalanceNew = _getBalance(swapParams.toToken, swapParams.isToNative);

      hopsAmountOut[hopId] = hopToTokenBalanceNew - hopToTokenBalanceOld;
      hopsAmountOutRest[hopId] = hopsAmountOut[hopId];

      uint256 executedAmountIn = hopFromTokenBalanceOld - hopFromTokenBalanceNew;
      uint256 restAmountIn = swapParams.amountIn - executedAmountIn;

      if (restAmountIn > 0) {
        _returnRestAmountIn(hops[i], hopsAmountOutRest, restAmountIn);
      }
    }
  }

  function _calculateHopAmountIn(
    Hop calldata hop,
    uint256[] memory hopsAmountOut,
    uint256[] memory hopsAmountOutRest,
    bool useForRest
  ) internal pure returns (uint256 amountIn) {
    for (uint i = 0; i < hop.inputHopParams.length; ++i) {
      (uint8 inputHopId, uint16 inputAmountPercent) = _unpackInputHopParams(hop.inputHopParams[i]);

      uint256 inputAmount = hopsAmountOut[inputHopId] * inputAmountPercent / 10000;
      amountIn += inputAmount;
      hopsAmountOutRest[inputHopId] -= inputAmount;

      // if hop used to swap amount rests or rest < 1/10000
      if (useForRest || hopsAmountOutRest[inputHopId] < hopsAmountOut[inputHopId] / 10000)  {
        amountIn += hopsAmountOutRest[inputHopId];
        hopsAmountOutRest[inputHopId] = 0;
      }
    }
  }

  function _returnRestAmountIn(
    Hop calldata hop,
    uint256[] memory hopsAmountOutRest,
    uint256 restAmountIn
  ) internal pure {
    for (uint i = hop.inputHopParams.length; i > 0; i--) {
      (uint8 inputHopId, uint16 inputAmountPercent) = _unpackInputHopParams(hop.inputHopParams[i - 1]);

      // if input used by more than one hop (<100%), try to return rest amount here
      if (inputAmountPercent < 10000) {
        hopsAmountOutRest[inputHopId] += restAmountIn;
        return;
      }
    }

    // no chance, throw the rest amount into any input
    (uint8 restHopId,) = _unpackInputHopParams(hop.inputHopParams[hop.inputHopParams.length - 1]);
    hopsAmountOutRest[restHopId] += restAmountIn;
  }

  function _refundRests(
    Hop[] calldata hops,
    uint256[] memory amountRests
  ) internal {
    // amountRests has length = hops.length + 1 and the following structure:
    // [amountIn rest, hops[0] output rest, hops[1] output rest, ..., hops[hops.length - 1] output = amountOut]
    //
    // with corresponding tokens:
    // [hops[-1].toToken = hops[0].fromToken, hops[0].toToken, hops[1].toToken, ..., hops[hops.length - 1].toToken]

    // try to refund all outputs except the last one
    for (uint i = 0; i < amountRests.length - 1; ++i) {
      if (amountRests[i] == 0) {
        continue;
      }

      uint hopIndex = i == 0 ? 0 : i - 1;

      (,, bool isFromNative, bool isToNative,) = _unpackParams(hops[hopIndex].params);

      (address token, bool isNative) = i == 0
        ? (hops[hopIndex].fromToken, isFromNative)
        : (hops[hopIndex].toToken, isToNative);

      if (isNative) {
        _sendETH(msg.sender, amountRests[i]);
      } else {
        IERC20(token).safeTransfer(msg.sender, amountRests[i]);
      }
    }
  }

  function _getBalance(address tokenAddress, bool isNative) internal view returns (uint256) {
    if (isNative) { // || tokenAddress == address(0)
      return address(this).balance;
    } else {
      return IERC20(tokenAddress).balanceOf(address(this));
    }
  }

  function _unwrapAndWrap(
    SwapParams memory params
  ) internal {
    if (params.fromToken != address(0) && !params.isFromNative) {
      IWETH fromTokenWeth = IWETH(params.fromToken);
      fromTokenWeth.withdraw(params.amountIn);
    }

    if (params.toToken != address(0) && !params.isToNative) {
      IWETH toTokenWeth = IWETH(params.toToken);
      toTokenWeth.deposit{value: params.amountIn}();
    }
  }

  function _swapUsingOnchainCLOB(
    SwapParams memory params
  ) internal {
    uint256 nativeAmountIn = 0;

    if (params.isFromNative) {
      nativeAmountIn = params.amountIn;
    } else {
      IERC20(params.fromToken).approve(params.routerAddress, params.amountIn);
    }

    IOnchainCLOB lob = IOnchainCLOB(payable(params.routerAddress));

    (
        uint256 scalingFactorTokenX,
        uint256 scalingFactorTokenY,
        address tokenX,
        ,
        ,
        ,
        ,
        ,
        ,
        ,
        ,
        ,
    ) = lob.getConfig();

    if (params.fromToken == tokenX) {
      // x -> y
      lob.placeOrder{value: nativeAmountIn}(
        true,
        uint128(params.amountIn / scalingFactorTokenX),
        1,
        type(uint128).max,
        true,
        false,
        true,
        params.deadline
      );
    } else {
      // y -> x
      lob.placeMarketOrderWithTargetValue{value: nativeAmountIn}(
        false,
        uint128(params.amountIn / scalingFactorTokenY),
        999999000000000000000,
        type(uint128).max,
        true,
        params.deadline
      );
    }
  }

  function _swapUsingV2Router(
    SwapParams memory params
  ) internal {
    uint256 nativeAmountIn = 0;

    if (params.isFromNative) {
      nativeAmountIn = params.amountIn;
    } else {
      IERC20(params.fromToken).approve(params.routerAddress, params.amountIn);
    }

    IV2Router router = IV2Router(params.routerAddress);

    address[] memory path = new address[](2);
    path[0] = params.fromToken;
    path[1] = params.toToken;

    if (params.isFromNative) {
      router.swapExactETHForTokens{value: nativeAmountIn}(
        0,
        path,
        address(this),
        params.deadline
      );
    } else if (params.isToNative) {
      router.swapExactTokensForETH(
        params.amountIn,
        0,
        path,
        address(this),
        params.deadline
      );
    } else {
      router.swapExactTokensForTokens(
        params.amountIn,
        0,
        path,
        address(this),
        params.deadline
      );
    }
  }

  function _swapUsingV3Router(
    SwapParams memory params
  ) internal {
    IERC20(params.fromToken).approve(params.routerAddress, params.amountIn);

    IV3Router router = IV3Router(params.routerAddress);

    IV3Router.ExactInputSingleParams memory v3params = IV3Router.ExactInputSingleParams({
      tokenIn: params.fromToken,
      tokenOut: params.toToken,
      fee: params.poolV3fee,
      recipient: address(this),
      deadline: params.deadline,
      amountIn: params.amountIn,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    router.exactInputSingle(v3params);
  }

  function _safeTansferFromWithBalanceCheck(
    IERC20 token,
    address from,
    address to,
    uint256 value
  ) internal {
    uint256 balanceBefore = token.balanceOf(address(this));
    token.safeTransferFrom(from, to, value);
    uint256 balanceAfter = token.balanceOf(address(this));
    require(balanceAfter - balanceBefore == value, Errors.InvalidTransfer());
  }

  function _sendETH(address to, uint256 value) internal {
    (bool success, ) = to.call{value: value}("");
    require(success, Errors.TransferFailed());
  }

  function _unpackInputHopParams(
    uint32 packedInputParams
  ) internal pure returns (uint8 hopId, uint16 amountPercent) {
    hopId = uint8(packedInputParams & 0xFF);
    amountPercent = uint16((packedInputParams >> 8) & 0xFFFF);
  }

  function _unpackParams(
    uint64 packedParams
  ) internal pure returns (
    uint8 dexId,
    bool useForRest,
    bool isFromNative,
    bool isToNative,
    uint24 poolV3fee
  ) {
    dexId = uint8(packedParams & 0xFF);
    useForRest = ((packedParams >> 8) & 0x1) > 0;
    isFromNative = ((packedParams >> 9) & 0x1) > 0;
    isToNative = ((packedParams >> 10) & 0x1) > 0;
    poolV3fee = uint24((packedParams >> 11) & 0xFFFFFF);
  }
}
