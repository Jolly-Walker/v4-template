// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IAToken} from "aave-v3-core/contracts/interfaces/IAToken.sol";
import {IPoolDataProvider} from "aave-v3-core/contracts/interfaces/IPoolDataProvider.sol";

contract Counter is BaseHook {
    using PoolIdLibrary for PoolKey;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------
    IPool public aavePool;
    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;

    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    // hookData: type: deposit/withdraw from aave
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 x = abi.decode(hookData, (uint256));
        if (x == 2) {
            aavePool.withdraw(Currency.unwrap(key.currency0), uint256(params.amountSpecified), sender);
        }
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        uint256 x = abi.decode(hookData, (uint256));

        if (params.zeroForOne && x == 1) {
            int128 amt = BalanceDeltaLibrary.amount1(delta);
            if (amt > 0) {
                uint256 amtOut =  uint256(uint128(amt));
                poolManager.take(key.currency1, address(this), amtOut);
                aavePool.supply(Currency.unwrap(key.currency1), amtOut, sender, 0);
                return (BaseHook.afterSwap.selector, amt);
            }
        } else if (x == 1) {
            int128 amt = BalanceDeltaLibrary.amount0(delta);
            if (amt > 0) {
                uint256 amtOut =  uint256(uint128(amt));
                poolManager.take(key.currency0, address(this), amtOut);
                aavePool.supply(Currency.unwrap(key.currency0), amtOut, sender, 0);
                return (BaseHook.afterSwap.selector, amt);
            }
        }
        return (BaseHook.afterSwap.selector, 0);
    }
}
