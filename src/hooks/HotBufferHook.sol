// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AaveHook} from "./AaveHook.sol";
import {RolesHook} from "./RolesHook.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";

/**
 * @title This hook introduces notion of a buffer to the aave hook to reduce
 * the number of deposits and withdrawals to aave during swaps.
 * Additionally it overrides deposits to fill buffer before supplying to aave.
 * todo: disable feature with 0 buffer
 */
abstract contract HotBufferHook is AaveHook, RolesHook {
    using SafeERC20 for IERC20Metadata;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // we will try to keep the the hook balance around the buffer size for both tokens
    uint256 public bufferSize0;
    uint256 public bufferSize1;

    // but in case we will need more tokens we would at least transfer this amount from AAVE
    // and in case there's an excess we will at least transfer this amount to AAVE
    uint256 public minTransferAmount0;
    uint256 public minTransferAmount1;

    constructor(uint256 _bufferSize0, uint256 _bufferSize1, uint256 _minTransferAmount0, uint256 _minTransferAmount1) {
        // Set values directly without computing unused decimals
        bufferSize0 = _bufferSize0;
        bufferSize1 = _bufferSize1;
        minTransferAmount0 = _minTransferAmount0;
        minTransferAmount1 = _minTransferAmount1;
    }

    function setBufferSize(uint256 _bufferSize0, uint256 _bufferSize1) external onlyHookManager {
        bufferSize0 = _bufferSize0;
        bufferSize1 = _bufferSize1;
    }

    function setMinTransferAmount(uint256 _minTransferAmount0, uint256 _minTransferAmount1) external onlyHookManager {
        minTransferAmount0 = _minTransferAmount0;
        minTransferAmount1 = _minTransferAmount1;
    }

    /**
     * @dev Buffer aware implementation of the _transferFees function
     * checks if we can route claim from AAVE if not - fallbacks to AAVE + buffer
     */
    function _transferFees(uint128 amount0, uint128 amount1, address treasury) internal virtual {
        _handleTransferFees(Currency.unwrap(token0), aToken0, amount0, treasury);
        _handleTransferFees(Currency.unwrap(token1), aToken1, amount1, treasury);
    }

    function _handleTransferFees(address token, address aToken, uint256 amount, address treasury) internal virtual {
        // 1. Withdraw from Aave to the hook

        uint256 aTokenBalance = 0;
        if (_tokenSupportedByAave(token)) {
            aTokenBalance = IERC20Metadata(aToken).balanceOf(address(this));
        }
        if (aTokenBalance >= amount) {
            _withdrawFromAave(token, amount, treasury);
            return;
        } else {
            uint256 bufferBalance = IERC20Metadata(token).balanceOf(address(this));
            uint256 amountToWithdraw = amount - bufferBalance;
            _withdrawFromAave(token, amountToWithdraw, address(this));

            IERC20Metadata(token).safeTransfer(treasury, amount);
        }
    }

    /**
     * @dev Buffer aware implementation of the _afterHookWithdraw function
     * tokens have already been transferred to the hook
     */
    function _afterHookDeposit(uint256 amount0, uint256 amount1, address) internal virtual override {
        _handleAfterHookDeposit(Currency.unwrap(token0), amount0, bufferSize0, minTransferAmount0);
        _handleAfterHookDeposit(Currency.unwrap(token1), amount1, bufferSize1, minTransferAmount1);
    }

    function _handleAfterHookDeposit(address token, uint256, uint256 bufferSize, uint256 minTransferAmount)
        internal
        virtual
    {
        uint256 tokenBuffer = IERC20Metadata(token).balanceOf(address(this));
        uint256 targetBalanceForDeposit = bufferSize + minTransferAmount;

        if (tokenBuffer > targetBalanceForDeposit) {
            // We have excess token in the buffer, deposit to Aave
            _depositToAave(token, tokenBuffer - bufferSize);
        }
    }

    /**
     * @dev Buffer aware implementation of the _afterHookWithdraw function
     * Checks if we have enough tokens in aave to withdraw, if yes - withdraws directly from aave
     * If has enough tokens in the buffer - withdraws from the buffer
     * In case we need to withdraw even more - firstly withdraws from aave and then buffer
     */
    function _afterHookWithdrawal(uint256 amount0, uint256 amount1, address receiver) internal virtual override {
        _handleAfterHookWithdrawal(Currency.unwrap(token0), aToken0, amount0, receiver, bufferSize0, minTransferAmount0);
        _handleAfterHookWithdrawal(Currency.unwrap(token1), aToken1, amount1, receiver, bufferSize1, minTransferAmount1);
    }

    function _handleAfterHookWithdrawal(
        address token,
        address aToken,
        uint256 amount,
        address receiver,
        uint256,
        uint256
    ) internal virtual {
        uint256 tokenBuffer = IERC20Metadata(token).balanceOf(address(this));
        uint256 aTokenBalance = 0;
        if (_tokenSupportedByAave(token)) {
            aTokenBalance = IERC20Metadata(aToken).balanceOf(address(this));
        }

        if (aTokenBalance >= amount) {
            _withdrawFromAave(token, amount, receiver);
        } else if (tokenBuffer >= amount) {
            IERC20Metadata(token).safeTransfer(receiver, amount);
        } else if (tokenBuffer + aTokenBalance >= amount) {
            _withdrawFromAave(token, aTokenBalance, address(this));
            IERC20Metadata(token).safeTransfer(receiver, amount);
        } else {
            revert("Not enough tokens in buffer or Aave");
        }
    }

    /**
     * @dev Main function to settle swaps with buffering logic
     * @param token0Delta Delta for token0 (positive means we're owed tokens)
     * @param token1Delta Delta for token1 (negative means we owe tokens)
     */
    function _settleSwap(int256 token0Delta, int256 token1Delta) internal virtual override {
        if (token0Delta > 0) {
            // We are owed token0 and owe token1
            _handleSwapSettlement(token0, token1, aToken1, uint256(token0Delta), uint256(-token1Delta));
        } else {
            // We are owed token1 and owe token0
            _handleSwapSettlement(token1, token0, aToken0, uint256(token1Delta), uint256(-token0Delta));
        }
    }

    /**
     * @dev Handles the swap settlement for a pair of tokens
     * @param receivedCurrency Currency we are receiving from pool manager
     * @param owedCurrency Currency we owe to pool manager
     * @param owedAToken aToken address for the currency we owe
     * @param receivedAmount Amount we are receiving
     * @param owedAmount Amount we owe
     */
    function _handleSwapSettlement(
        Currency receivedCurrency,
        Currency owedCurrency,
        address owedAToken,
        uint256 receivedAmount,
        uint256 owedAmount
    ) private {
        // 1. Take the tokens we are owed from pool manager
        poolManager.take(receivedCurrency, address(this), receivedAmount);

        // 2. Handle tokens we owe
        uint256 bufferSize = owedCurrency == token0 ? bufferSize0 : bufferSize1;
        uint256 minTransferAmount = owedCurrency == token0 ? minTransferAmount0 : minTransferAmount1;
        _handleOwedTokensPayment(owedCurrency, owedAToken, owedAmount, bufferSize, minTransferAmount);

        // 3. Check if we should deposit excess of received tokens
        uint256 recvBufferSize = receivedCurrency == token0 ? bufferSize0 : bufferSize1;
        uint256 recvMinTransferAmount = receivedCurrency == token0 ? minTransferAmount0 : minTransferAmount1;
        _checkAndDepositExcess(receivedCurrency, recvBufferSize, recvMinTransferAmount);
    }

    /**
     * @dev Handle payment of tokens we owe to the pool manager
     * @param owedCurrency Currency we owe to pool manager
     * @param aTokenAddress aToken address for the currency
     * @param owedAmount Amount we owe
     */
    function _handleOwedTokensPayment(
        Currency owedCurrency,
        address aTokenAddress,
        uint256 owedAmount,
        uint256 bufferSize,
        uint256 minTransferAmount
    ) private {
        address unwrappedToken = Currency.unwrap(owedCurrency);
        uint256 currentBalance = IERC20Metadata(unwrappedToken).balanceOf(address(this));

        if (currentBalance >= owedAmount) {
            // We have enough balance to pay directly
            _payDirectlyFromBalance(owedCurrency, owedAmount);
        } else {
            // this shouldn't happen for tokens not supported by aave as that would mean we swapped more than what we have and should revert
            // We need to withdraw from Aave
            _withdrawAndPayWithBuffer(
                owedCurrency, aTokenAddress, owedAmount, currentBalance, bufferSize, minTransferAmount
            );
        }
    }

    /**
     * @dev Pay directly from the hook's balance
     * @param currency Currency to pay
     * @param amount Amount to pay
     */
    function _payDirectlyFromBalance(Currency currency, uint256 amount) private {
        poolManager.sync(currency);
        IERC20Metadata(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
        poolManager.settle();
    }

    /**
     * @dev Withdraw from Aave and pay with buffer logic
     * @param currency Currency to withdraw and pay
     * @param aTokenAddress aToken address for the currency
     * @param owedAmount Amount we owe
     * @param currentBalance Current balance of the token
     */
    function _withdrawAndPayWithBuffer(
        Currency currency,
        address aTokenAddress,
        uint256 owedAmount,
        uint256 currentBalance,
        uint256 bufferSize,
        uint256
    ) private {
        uint256 aTokenBalance = 0;
        if (_tokenSupportedByAave(Currency.unwrap(currency))) {
            aTokenBalance = IERC20Metadata(aTokenAddress).balanceOf(address(this));
        }
        // Calculate how much to withdraw to maintain target buffer size
        uint256 amountToWithdraw = _calculateWithdrawalAmount(owedAmount, currentBalance, aTokenBalance, bufferSize);

        // Withdraw from Aave to the hook
        poolManager.sync(currency);
        _withdrawFromAave(Currency.unwrap(currency), amountToWithdraw, address(this));

        // Pay the owed amount to pool manager
        IERC20Metadata(Currency.unwrap(currency)).safeTransfer(address(poolManager), owedAmount);
        poolManager.settle();
    }

    /**
     * @dev Calculate the optimal amount to withdraw from Aave
     * @param owedAmount Amount we owe
     * @param currentBalance Current balance of the token
     * @param aTokenBalance Current aToken balance
     * @return Amount to withdraw from Aave
     */
    function _calculateWithdrawalAmount(
        uint256 owedAmount,
        uint256 currentBalance,
        uint256 aTokenBalance,
        uint256 bufferSize
    ) private pure returns (uint256) {
        uint256 amountToWithdraw = owedAmount;
        // nothing to withdraw
        if (aTokenBalance == 0) {
            return 0;
        }

        // If current balance after paying would be less than 0
        // withdraw from aave to cover the owed amount and maintain buffer size
        if (currentBalance < owedAmount) {
            amountToWithdraw = (owedAmount + bufferSize) - currentBalance;
        }

        // Cap withdrawal at available aToken balance
        // If the swap needs more - the TX will fail
        return amountToWithdraw > aTokenBalance ? aTokenBalance : amountToWithdraw;
    }

    /**
     * @dev Check if we should deposit excess tokens to Aave
     * @param currency Currency to check for excess
     */
    function _checkAndDepositExcess(Currency currency, uint256 bufferSize, uint256 minTransferAmount) private {
        address unwrappedToken = Currency.unwrap(currency);
        uint256 newBalance = IERC20Metadata(unwrappedToken).balanceOf(address(this));

        // Check if the new balance exceeds the buffer size + min transfer amount
        // if so, move all above buffer to AAVE
        if (newBalance > bufferSize + minTransferAmount) {
            uint256 excessAmount = newBalance - bufferSize;
            _depositToAave(unwrappedToken, excessAmount);
        }
    }
}
