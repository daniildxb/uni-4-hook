// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CustodyHook} from "./CustodyHook.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

/**
 * @title Fee Tracking Hook
 * @notice Hook that tracks fees earned from liquidity provision and lending yield
 * todo: consider decoupling from AaveHook
 */
abstract contract FeeTrackingHook is CustodyHook {
    event FeesTracked(uint256 feeDelta);
    event FeesCollected(uint256 liquidityCollected, uint256 amount0, uint256 amount1, address treasury);

    using SafeCast for *;
    // measured in liquidity

    uint256 public unclaimedFees;
    uint256 public lastSeenAssets;
    address public feeCollector;
    // todo: switch to lower precision
    uint256 public fee_bps;

    constructor(address _feeCollector, uint256 _fee_bps) {
        require(_feeCollector != address(0), "Zero address");
        feeCollector = _feeCollector;
        fee_bps = _fee_bps;
    }

    modifier onlyFeeCollector() {
        require(msg.sender == feeCollector, "Not fee collector");
        _;
    }

    // needs to be added on any method that can change liquidity of the pool
    modifier trackFeesBefore() {
        _trackFees();
        _;
    }

    // needs to be called after any method that can change liquidity of the pool
    modifier setAssetsAfter() {
        _;
        lastSeenAssets = totalAssets();
    }

    // substracting fees from total assets so that new depositors don't get slashed
    // when we withdraw fees
    function totalAssets() public view virtual override returns (uint256) {
        return super.totalAssets() - unclaimedFees;
    }

    function _transferFees(uint128 amount0, uint128 amount1, address treasury) internal virtual;
    function getUnclaimedFees() public view virtual returns (int128 amount0, int128 amount1);

    function collectFees() external virtual onlyFeeCollector returns (uint128 amount0, uint128 amount1) {
        (int128 _amount0, int128 _amount1) = getUnclaimedFees();
        require(_amount0 > 0 || _amount1 > 0, "No fees to collect");
        amount0 = _amount0.toUint128();
        amount1 = _amount1.toUint128();
        unclaimedFees = 0;
        _transferFees(amount0, amount1, feeCollector);
        lastSeenAssets = totalAssets();
        emit FeesCollected(unclaimedFees, amount0, amount1, feeCollector);
    }

    function _setFeeCollector(address _feeCollector) internal {
        feeCollector = _feeCollector;
    }

    // needs to be called on any method that can change liquidity of the pool
    function _trackFees() internal {
        uint256 newProtocolLiquidity = totalAssets();
        if (newProtocolLiquidity <= lastSeenAssets) {
            return;
        }

        uint256 liquidityDelta = newProtocolLiquidity - lastSeenAssets;
        // todo: add ray math here
        uint256 fees = liquidityDelta * fee_bps / 1e4;
        unclaimedFees += fees;
        lastSeenAssets = newProtocolLiquidity;

        emit FeesTracked(fees);
    }
}
