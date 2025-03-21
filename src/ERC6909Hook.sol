// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;


import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IAToken} from "aave-v3-core/contracts/interfaces/IAToken.sol";
import {IPoolDataProvider} from "aave-v3-core/contracts/interfaces/IPoolDataProvider.sol";
import {IERC6909Claims} from "v4-core/src/interfaces/external/IERC6909Claims.sol";

/**
 * @title ERC6909SwapOptimizer
 * @notice Hook that optimizes gas by using ERC6909 for frequent swappers
 */
contract ERC6909SwapOptimizer is BaseHook {
    using SafeCast for *;
    // Track the minimum token amount worth converting to ERC6909
    uint256 public immutable MIN_AMOUNT_TO_MINT;
    
    // Track user preferences
    mapping(address => bool) public userOptedIn;
    
    // Track pending transfers
    struct PendingTransfer {
        address recipient;
        Currency currency;
        uint256 amount;
        bool useERC6909;
    }
    
    // Track input tokens that need to be provided from ERC6909 balances
    struct InputTokenRedemption {
        address user;
        Currency currency;
        uint256 amount;
    }
    
    mapping(bytes32 => PendingTransfer) public pendingTransfers;
    mapping(bytes32 => InputTokenRedemption) public inputRedemptions;
    
    // Event when ERC6909 tokens are used for swap input
    event ERC6909UsedForSwap(address indexed user, Currency indexed currency, uint256 amount);
    
    constructor(IPoolManager _poolManager, uint256 _minAmountToMint) BaseHook(_poolManager) {
        MIN_AMOUNT_TO_MINT = _minAmountToMint;
    }
    
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
    
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // If user hasn't opted in, return without modifications
        if (!userOptedIn[sender]) {
            return (BaseHook.afterSwap.selector, 0);
        }
        
        // Determine which token the user is receiving
        BalanceDelta hookDelta = BalanceDeltaLibrary.ZERO_DELTA;
        Currency receivedCurrency;
        int128 receivedAmount;
        
        if (params.zeroForOne && delta.amount1() < 0) {
            // User is receiving token1
            receivedCurrency = key.currency1;
            receivedAmount = -delta.amount1(); // Convert negative to positive
            
            hookDelta = toBalanceDelta(0, delta.amount1());
            // Zero out the user's token1 receipt
            delta = toBalanceDelta(delta.amount0(), 0);
            
        } else if (!params.zeroForOne && delta.amount0() < 0) {
            // User is receiving token0
            receivedCurrency = key.currency0;
            receivedAmount = -delta.amount0(); // Convert negative to positive
        
            hookDelta = toBalanceDelta(delta.amount0(), 0);
            delta = toBalanceDelta(0, delta.amount1());
        } else {
            // User is not receiving tokens (e.g., a failed swap)
            return (BaseHook.afterSwap.selector, 0);
        }

        uint256 tokenId = CurrencyLibrary.toId(receivedCurrency);
        poolManager.mint(sender, tokenId, uint256(uint128(receivedAmount)));

        return (BaseHook.afterSwap.selector, receivedAmount);
    }
    
}