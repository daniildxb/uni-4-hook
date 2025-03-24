// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {MockAToken} from "./MockAToken.sol";
import "forge-std/Test.sol";

contract MockAavePool is Test {
    address public token0;
    address public token1;
    MockAToken public aToken0;
    MockAToken public aToken1;

    constructor(address _token0, MockAToken _aToken0, address _token1, MockAToken _aToken1) {
        token0 = _token0;
        token1 = _token1;
        aToken0 = _aToken0;
        aToken1 = _aToken1;
    }

    function getReserveData(address token) public view returns (DataTypes.ReserveData memory) {
        console.log("getReserveData");
        if (token == token0) {
            console.log("token0");
            return _getReserveData0();
        } else if (token == token1) {
            console.log("token1");
            return _getReserveData1();
        } else {
            console.log("fuck");
            revert("INVALID_TOKEN");
        }
    }

    function supply(address asset, uint256 amount, address receiver, uint16) public {
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        if (asset == token0) {
            aToken0.mint(address(this), receiver, amount);
            ERC20(asset).transfer(address(aToken0), amount);
        } else if (asset == token1) {
            aToken1.mint(address(this), receiver, amount);
            ERC20(asset).transfer(address(aToken1), amount);
        } else {
            revert("INVALID_ASSET");
        }
    }

    function withdraw(address asset, uint256 amount, address receiver) public returns (uint256) {
        uint256 actualAmount = amount;
        if (asset == token0) {
            if (amount == type(uint256).max) {
                actualAmount = aToken0.balanceOf(msg.sender);
            }
            aToken0.burn(msg.sender, receiver, actualAmount);
        } else if (asset == token1) {
            if (amount == type(uint256).max) {
                actualAmount = aToken1.balanceOf(msg.sender);
            }
            aToken1.burn(msg.sender, receiver, actualAmount);
        } else {
            revert("INVALID_ASSET");
        }
        return actualAmount;
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
