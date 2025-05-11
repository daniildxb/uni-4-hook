// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AaveHook} from "./AaveHook.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
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
abstract contract HotBufferHook is AaveHook {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // we will try to keep the the hook balance around the buffer size for both tokens
    uint256 public bufferSize;

    // but in case we will need more tokens we would at least transfer this amount from AAVE
    // and in case there's an excess we will at least transfer this amount to AAVE
    uint256 public minTransferAmount;

    constructor(uint256 _bufferSize, uint256 _minTransferAmount) {
        bufferSize = _bufferSize;
        minTransferAmount = _minTransferAmount;
    }

    // todo: add RBAC
    function setBufferSize(uint256 _bufferSize) external {
        require(msg.sender == admin, "Not owner");
        bufferSize = _bufferSize;
    }

    // todo: add RBAC
    function setMinTransferAmount(uint256 _minTransferAmount) external {
        require(msg.sender == admin, "Not owner");
        minTransferAmount = _minTransferAmount;
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
        uint256 aTokenBalance = IERC20(aToken).balanceOf(address(this));
        if (aTokenBalance >= amount) {
            _withdrawFromAave(token, amount, treasury);
            return;
        } else {
            uint256 bufferBalance = IERC20(token).balanceOf(address(this));
            uint256 amountToWithdraw = amount - bufferBalance;
            _withdrawFromAave(token, amountToWithdraw, address(this));

            IERC20(token).safeTransfer(treasury, amount);
        }
    }

    /**
     * @dev Buffer aware implementation of the _afterHookWithdraw function
     * tokens have already been transferred to the hook
     */
    function _afterHookDeposit(uint256 amount0, uint256 amount1) internal virtual override {
        _handleAfterHookDeposit(Currency.unwrap(token0), amount0);
        _handleAfterHookDeposit(Currency.unwrap(token1), amount1);
    }

    function _handleAfterHookDeposit(address token, uint256 amount) internal virtual {
        uint256 tokenBuffer = IERC20(token).balanceOf(address(this));
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
        _handleAfterHookWithdrawal(Currency.unwrap(token0), aToken0, amount0, receiver);
        _handleAfterHookWithdrawal(Currency.unwrap(token1), aToken1, amount1, receiver);
    }

    function _handleAfterHookWithdrawal(address token, address aToken, uint256 amount, address receiver)
        internal
        virtual
    {
        uint256 tokenBuffer = IERC20(token).balanceOf(address(this));
        uint256 aTokenBalance = IERC20(aToken).balanceOf(address(this));

        if (aTokenBalance >= amount) {
            _withdrawFromAave(token, amount, receiver);
        } else if (tokenBuffer >= amount) {
            IERC20(token).safeTransfer(receiver, amount);
        } else if (tokenBuffer + aTokenBalance >= amount) {
            _withdrawFromAave(token, aTokenBalance, address(this));
            IERC20(token).safeTransfer(receiver, amount);
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
        _handleOwedTokensPayment(owedCurrency, owedAToken, owedAmount);

        // 3. Check if we should deposit excess of received tokens
        _checkAndDepositExcess(receivedCurrency);
    }

    /**
     * @dev Handle payment of tokens we owe to the pool manager
     * @param owedCurrency Currency we owe to pool manager
     * @param aTokenAddress aToken address for the currency
     * @param owedAmount Amount we owe
     */
    function _handleOwedTokensPayment(Currency owedCurrency, address aTokenAddress, uint256 owedAmount) private {
        address unwrappedToken = Currency.unwrap(owedCurrency);
        uint256 currentBalance = IERC20(unwrappedToken).balanceOf(address(this));

        if (currentBalance >= owedAmount) {
            // We have enough balance to pay directly
            _payDirectlyFromBalance(owedCurrency, owedAmount);
        } else {
            // We need to withdraw from Aave
            _withdrawAndPayWithBuffer(owedCurrency, aTokenAddress, owedAmount, currentBalance);
        }
    }

    /**
     * @dev Pay directly from the hook's balance
     * @param currency Currency to pay
     * @param amount Amount to pay
     */
    function _payDirectlyFromBalance(Currency currency, uint256 amount) private {
        poolManager.sync(currency);
        IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
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
        uint256 currentBalance
    ) private {
        // Calculate how much to withdraw to maintain target buffer size
        uint256 amountToWithdraw =
            _calculateWithdrawalAmount(owedAmount, currentBalance, IERC20(aTokenAddress).balanceOf(address(this)));

        // Withdraw from Aave to the hook
        poolManager.sync(currency);
        _withdrawFromAave(Currency.unwrap(currency), amountToWithdraw, address(this));

        // Pay the owed amount to pool manager
        IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), owedAmount);
        poolManager.settle();
    }

    /**
     * @dev Calculate the optimal amount to withdraw from Aave
     * @param owedAmount Amount we owe
     * @param currentBalance Current balance of the token
     * @param aTokenBalance Current aToken balance
     * @return Amount to withdraw from Aave
     */
    function _calculateWithdrawalAmount(uint256 owedAmount, uint256 currentBalance, uint256 aTokenBalance)
        private
        view
        returns (uint256)
    {
        uint256 amountToWithdraw = owedAmount;

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
    function _checkAndDepositExcess(Currency currency) private {
        address unwrappedToken = Currency.unwrap(currency);
        uint256 newBalance = IERC20(unwrappedToken).balanceOf(address(this));

        // Check if the new balance exceeds the buffer size + min transfer amount
        // if so, move all above buffer to AAVE
        if (newBalance > bufferSize + minTransferAmount) {
            uint256 excessAmount = newBalance - bufferSize;
            _depositToAave(unwrappedToken, excessAmount);
        }
    }
}
