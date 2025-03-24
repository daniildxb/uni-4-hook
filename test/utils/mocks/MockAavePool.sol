// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {MockAToken} from "./MockAToken.sol";

contract MockAavePool {
    address public token0;
    address public token1;
    MockAToken public aToken0;
    MockAToken public aToken1;

    constructor(address token0, MockAToken _aToken0, address token1, MockAToken _aToken1) {
        token0 = token0;
        token1 = token1;
        aToken0 = _aToken0;
        aToken1 = _aToken1;
    }

    function getReserveData(address token) public view returns (DataTypes.ReserveData memory) {
        if (token == token0) {
            return _getReserveData0();
        } else if (token == token1) {
            return _getReserveData1();
        } else {
            revert("INVALID_TOKEN");
        }
    }

    function _getReserveData0() internal view returns (DataTypes.ReserveData memory) {
        return DataTypes.ReserveData({
            configuration: DataTypes.ReserveConfigurationMap(0),
            liquidityIndex: 0,
            currentLiquidityRate: 0,
            variableBorrowIndex: 0,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: 0,
            id: 0,
            aTokenAddress: address(aToken0),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }

    function _getReserveData1() internal view returns (DataTypes.ReserveData memory) {
        return DataTypes.ReserveData({
            configuration: DataTypes.ReserveConfigurationMap(0),
            liquidityIndex: 0,
            currentLiquidityRate: 0,
            variableBorrowIndex: 0,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: 0,
            id: 0,
            aTokenAddress: address(aToken1),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }
}
