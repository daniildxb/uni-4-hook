// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IHookManager} from "./interfaces/IHookManager.sol";
// aggregated interface of all RBAC methods on hooks

interface IHook {
    function key() external view returns (PoolKey memory);
    function setBufferSize(uint256 bufferSize0, uint256 bufferSize1) external;
    function setMinTransferAmount(uint256 minTransferAmount0, uint256 minTransferAmount1) external;
    function setDepositCaps(uint256 depositCap0, uint256 depositCap1) external;
    function flipAllowlist() external;
    function isAllowlistEnabled() external returns (bool);
    function flipAddressInAllowList(address addr) external;
    function flipSwapperAllowlist() external;
    function flipAddressInSwapperAllowList(address addr) external;
    function setFeeBps(uint256 feeBps) external;
    function collectFees() external;
    function rescue(address token, uint256 amount, address to) external;
}

interface IExecutor {
    function registerPool(PoolKey calldata key) external;
    function unwrapWETH(address to) external;
    function withdrawETH(address to) external;
    function rescue(address token, uint256 amount, address to) external;
}

contract HookManager is IHookManager, Ownable {
    using PoolIdLibrary for PoolKey;

    address public constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    address public poolManager;
    uint256 public hookCount = 0;
    uint256 public executorCount = 0;

    mapping(PoolId => address) public poolIdToHook;
    mapping(address => PoolId) public hookToPoolId;
    mapping(uint256 => address) public indexToHook;
    mapping(uint256 => address) public indexToExecutor;

    constructor(address _poolManager, address _owner) Ownable(_owner) {
        poolManager = _poolManager;
    }

    modifier isValidHook(address hook) {
        require(PoolId.unwrap(hookToPoolId[hook]) != bytes32(0), "Hook not found");
        _;
    }

    /**
     * @notice Deploys a ModularHookV1 hook with CREATE2 and initializes it
     * @param token0 The first currency for the pool
     * @param token1 The second currency for the pool
     * @param expectedAddress The expected address of the hook (for verification)
     * @param sqrtPriceX96 The initial sqrt price for the pool
     * @param fee The fee tier for the pool
     * @param tickSpacing The tick spacing for the pool
     * @param salt The salt for CREATE2 deployment
     * @param creationCode The creation bytecode of the hook with constructor args
     */
    function deployHook(
        Currency token0,
        Currency token1,
        address expectedAddress,
        uint160 sqrtPriceX96,
        uint24 fee,
        int24 tickSpacing,
        bytes32 salt,
        bytes calldata creationCode
    ) external onlyOwner {
        // Deploy the hook using CREATE2
        address hookAddress = Create2.deploy(0, salt, creationCode);

        // Verify the expected address matches
        require(hookAddress == expectedAddress, "Hook address mismatch");

        // Initialize the pool and add it to the hook
        PoolKey memory key = PoolKey(token0, token1, fee, tickSpacing, IHooks(hookAddress));
        IPoolManager(poolManager).initialize(key, sqrtPriceX96);

        // Track the hook
        PoolId poolId = key.toId();
        _storeHook(hookAddress, poolId);
        _addHookToExecutors(key);
        emit HookDeployed(hookAddress, poolId, hookCount, sqrtPriceX96);
        hookCount++;
    }

    function addExecutor(address executor) external onlyOwner {
        require(executor != address(0), "Invalid executor address");
        indexToExecutor[executorCount] = executor;
        IExecutor executorContract = IExecutor(executor);
        for (uint256 i = 0; i < hookCount; i++) {
            IHook hook = IHook(indexToHook[i]);
            PoolKey memory key = hook.key();
            executorContract.registerPool(key);
        }

        emit ExecutorAdded(executor, executorCount);
        executorCount++;
    }

    function getAllHooks() external view returns (address[] memory) {
        address[] memory hooks = new address[](hookCount);
        for (uint256 i = 0; i < hookCount; i++) {
            address hookAddress = indexToHook[i];
            hooks[i] = hookAddress;
        }
        return hooks;
    }

    function setBufferSize(address hook, uint256 bufferSize0, uint256 bufferSize1)
        external
        onlyOwner
        isValidHook(hook)
    {
        IHook(hook).setBufferSize(bufferSize0, bufferSize1);
    }

    function setMinTransferAmount(address hook, uint256 minTransferAmount0, uint256 minTransferAmount1)
        external
        onlyOwner
        isValidHook(hook)
    {
        IHook(hook).setMinTransferAmount(minTransferAmount0, minTransferAmount1);
    }

    function setDepositCap(address hook, uint256 depositCap0, uint256 depositCap1)
        external
        onlyOwner
        isValidHook(hook)
    {
        IHook(hook).setDepositCaps(depositCap0, depositCap1);
        emit DepositCapSet(hook, depositCap0, depositCap1);
    }

    function flipAllowlist(address hook) external onlyOwner isValidHook(hook) {
        IHook(hook).flipAllowlist();
        bool isAllowlistEnabled = IHook(hook).isAllowlistEnabled();
        emit AllowlistFlipped(hook, isAllowlistEnabled);
    }

    function flipAddressInAllowList(address hook, address addr) external onlyOwner isValidHook(hook) {
        IHook(hook).flipAddressInAllowList(addr);
    }

    function flipSwapperAllowlist(address hook) external onlyOwner isValidHook(hook) {
        IHook(hook).flipSwapperAllowlist();
    }

    function flipAddressInSwapperAllowList(address hook, address addr) external onlyOwner isValidHook(hook) {
        IHook(hook).flipAddressInSwapperAllowList(addr);
    }

    function setFeeBps(address hook, uint256 feeBps) external onlyOwner isValidHook(hook) {
        IHook(hook).setFeeBps(feeBps);
        emit FeeBpsUpdated(hook, feeBps);
    }

    function collectFees(address hook) external onlyOwner isValidHook(hook) {
      // hook emits event with more details
        IHook(hook).collectFees();
        emit FeesCollected(hook);
    }

    function rescue(address hook, address token, uint256 amount, address to) external onlyOwner isValidHook(hook) {
        IHook(hook).rescue(token, amount, to);
    }

    function unwrapExecutorETH(uint256 executorIndex, address to) external onlyOwner {
        require(executorIndex < executorCount, "Invalid executor index");
        address executor = indexToExecutor[executorIndex];
        IExecutor executorContract = IExecutor(executor);
        executorContract.unwrapWETH(to);
    }

    function withdrawExecutorETH(uint256 executorIndex, address to) external onlyOwner {
        require(executorIndex < executorCount, "Invalid executor index");
        address executor = indexToExecutor[executorIndex];
        IExecutor executorContract = IExecutor(executor);
        executorContract.withdrawETH(to);
    }

    function rescueExecutorERC20(uint256 executorIndex, address token, uint256 amount, address to) external onlyOwner {
        require(executorIndex < executorCount, "Invalid executor index");
        address executor = indexToExecutor[executorIndex];
        IExecutor executorContract = IExecutor(executor);
        executorContract.rescue(token, amount, to);
    }

    /**
     * @dev Stores a hook in the registry
     * @param hook The address of the hook
     * @param poolId The pool ID associated with the hook
     */
    function _storeHook(address hook, PoolId poolId) internal {
        require(poolIdToHook[poolId] == address(0), "Hook already exists for this poolId");
        poolIdToHook[poolId] = hook;
        hookToPoolId[hook] = poolId;
        indexToHook[hookCount] = hook;
    }

    function _addHookToExecutors(PoolKey memory key) internal {
        for (uint256 i = 0; i < executorCount; i++) {
            address executor = indexToExecutor[i];
            IExecutor executorContract = IExecutor(executor);
            executorContract.registerPool(key);
        }
    }
}
