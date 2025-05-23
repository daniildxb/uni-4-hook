// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Config} from "./base/Config.sol";
import {ModularHookV1} from "src/ModularHookV1.sol";
import {HookManager} from "src/HookManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolIdLibrary, PoolId} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";

// UniswapX imports
import {
    SignedOrder, ResolvedOrder, OrderInfo, InputToken, OutputToken
} from "lib/UniswapX/src/base/ReactorStructs.sol";
import {
    PriorityOrderLib,
    PriorityOrder,
    PriorityInput,
    PriorityOutput,
    PriorityCosignerData
} from "lib/UniswapX/src/lib/PriorityOrderLib.sol";
import {CosignerLib} from "lib/UniswapX/src/lib/CosignerLib.sol";

/// @notice Script for adhoc usage
contract AdHocScript is Script, Deployers, Config {
    using SafeCast for *;
    using SafeERC20 for IERC20;
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using PriorityOrderLib for PriorityOrder;

    HookManager public hookManager;

    struct OrderRoutingData {
        bytes32 poolId;
    }

    // ===== Test data =====
    // The actual test order encoded as bytes
    bytes constant TEST_ORDER_ENCODED =
        hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000014000000000000000000000000032342160970439ad083041cbf91836936be66df20000000000000000000000000000000000000000000000000000000001d2e42a00000000000000000000000000000000000000000000000000000000000000010000000000000000000000006bb7a212910682dcfdbd5bcbb3e28fb4e8da10ee0000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000001d2e42200000000000000000000000000000000000000000000000000000000000002c0000000000000000000000000000000001ec5656dcdb24d90dfa42742738de7290000000000000000000000008c3d9a0312890527afc6ae4ee16ca263fbb0dccd000000000000000000000000000000000000000000000000000000000000007a0000000000000000000000000000000000000000000000000000000068303334000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000000000000000000000000000000dbba000000000000000000000000000000000000000000000000000000000000027100000000000000000000000008c3d9a0312890527afc6ae4ee16ca263fbb0dccd00000000000000000000000000000000000000000000000000000000000000414ece6fedac5b3aba046ed23986f2eb97cf0921aa41d13107f88e3f9a22c354b0532ccd91601e062a2ef1f60e6cce4f0052e130851aa38fb91b5d22bebf72c90a1c00000000000000000000000000000000000000000000000000000000000000";

    // The signature from the swapper
    bytes constant TEST_ORDER_SIG =
        hex"73f0038c93978c861eba2b2d17c7d12538723e5c4701e78a7462dcf4b3fae0b25c9aa5066356138b83c99cef2594781b4cd6accd6e985a1b4cab85000b3bf29d1c";

    /**
     * @notice Decode and verify the test order using the actual UniswapX libraries
     * @dev This function decodes the test order data and verifies the cosignature using CosignerLib
     */
    function testOrderVerification() internal view {
        console.log("\n=== TEST ORDER VERIFICATION USING UNISWAP LIBRARIES ===");

        // 1. Decode the order
        PriorityOrder memory order = abi.decode(TEST_ORDER_ENCODED, (PriorityOrder));

        // 2. Display order details
        console.log("Order details:");
        console.log("- Swapper:", order.info.swapper);
        console.log("- Deadline:", order.info.deadline);
        console.log("- Cosigner:", order.cosigner);
        console.log("- Auction start block:", order.auctionStartBlock);
        console.log("- Auction target block (from cosigner):", order.cosignerData.auctionTargetBlock);

        // 3. Calculate the order hash using PriorityOrderLib
        bytes32 orderHash = order.hash();
        console.log("Order hash:", vm.toString(orderHash));
        console.log("chain id:", block.chainid);
        // 4. Calculate the cosigner digest using PriorityOrderLib
        bytes32 cosignerDigest = order.cosignerDigest(orderHash);
        console.log("Cosigner digest:", vm.toString(cosignerDigest));

        // 5. Extract the signature components for display
        (bytes32 r, bytes32 s, uint8 v) = extractSignatureComponents(order.cosignature);

        console.log("Cosignature components:");
        console.log("- r:", vm.toString(r));
        console.log("- s:", vm.toString(s));
        console.log("- v:", v);

        // 6. Verify using CosignerLib's verify function (this will revert if invalid)
        // CosignerLib.verify(order.cosigner, cosignerDigest, order.cosignature);

        // 7. Also check with direct ecrecover for comparison
        address recoveredSigner = ecrecover(cosignerDigest, v, r, s);
        console.log("Recovered signer:", recoveredSigner);
        console.log("Expected cosigner:", order.cosigner);
        console.log("Matches expected:", recoveredSigner == order.cosigner);
    }

    /**
     * @notice Extract r, s, v components from a signature
     * @param signature The signature to parse
     * @return r The r component
     * @return s The s component
     * @return v The v component
     */
    function extractSignatureComponents(bytes memory signature) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(signature.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        return (r, s, v);
    }

    /**
     * @notice Recreate validation logic from PriorityOrderReactor._validateOrder
     * @param order The order to validate
     */
    function validateOrder(PriorityOrder memory order) internal view {
        console.log("\n=== VALIDATING ORDER LIKE PRIORITYORDERREACTOR ===");

        // Calculate the order hash
        bytes32 orderHash = order.hash();

        // 1. Check deadline
        if (order.info.deadline < block.timestamp) {
            console.log("Validation failed: Order deadline is in the past");
            return;
        } else {
            console.log("Deadline is valid");
        }

        // 2. Check auction start block and cosigner
        uint256 auctionStartBlock = order.auctionStartBlock;

        if (
            order.cosigner != address(0) && block.number < auctionStartBlock
                && order.cosignerData.auctionTargetBlock < auctionStartBlock
        ) {
            // Verify cosignature
            CosignerLib.verify(order.cosigner, order.cosignerDigest(orderHash), order.cosignature);
        }

        // 3. Check if auction start block is in the future
        if (block.number < auctionStartBlock) {
            console.log("Validation failed: Order not fillable yet (auction start block is in the future)");
            return;
        } else {
            console.log("Order is fillable (auction has started)");
        }

        // 4. Check for input/output scaling conflicts
        if (order.input.mpsPerPriorityFeeWei > 0) {
            for (uint256 i = 0; i < order.outputs.length; i++) {
                if (order.outputs[i].mpsPerPriorityFeeWei > 0) {
                    console.log("Validation failed: Both input and outputs scale with priority fee");
                    return;
                }
            }
        }
        console.log("Priority fee scaling is valid");

        console.log("Order passed all validation checks");
    }

    function signatureVerificaitons() internal {
        // Test verification using UniswapX libraries
        testOrderVerification();

        // Test validation logic like in PriorityOrderReactor
        PriorityOrder memory order = abi.decode(TEST_ORDER_ENCODED, (PriorityOrder));
        validateOrder(order);
    }

    /**
     * @notice Run all verification tests
     */
    function run() public {
        // signatureVerificaitons();
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 pool_enum = vm.envUint("POOL_ENUM"); // 0 USDC/USDT ; 1 USDT/DAI

        // callback data - 0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020cf3950f1dbdeb560dd0270f2ac8c8196c227cd4cf78165daaaa7f4676c28be55
        bytes memory callbackData =
            hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020cf3950f1dbdeb560dd0270f2ac8c8196c227cd4cf78165daaaa7f4676c28be55";
        OrderRoutingData memory routingData = abi.decode(callbackData, (OrderRoutingData));

        console.log("pool id");
        console.logBytes32(routingData.poolId);
    }
}
