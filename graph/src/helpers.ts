import { BigInt, BigDecimal, Address } from '@graphprotocol/graph-ts';
import { 
  ERC20 
} from '../generated/HookV1/ERC20';
import {
  Token,
  Pool,
  Protocol,
} from '../generated/schema';

export let ZERO_BI = BigInt.fromI32(0);
export let ONE_BI = BigInt.fromI32(1);
export let ZERO_BD = BigDecimal.fromString('0');
export let ONE_BD = BigDecimal.fromString('1');
export let BI_18 = BigInt.fromI32(18);


export function loadToken(tokenAddress: Address): Token {
  let token = Token.load(tokenAddress.toHexString());
  
  if (token === null) {
    token = new Token(tokenAddress.toHexString());
    let tokenContract = ERC20.bind(tokenAddress);
    
    // Try to load token data - handle potential contract call failures
    let tokenSymbol = '';
    let tokenName = '';
    let tokenDecimals = 0;
    
    let symbolResult = tokenContract.try_symbol();
    if (!symbolResult.reverted) {
      tokenSymbol = symbolResult.value;
    }
    
    let nameResult = tokenContract.try_name();
    if (!nameResult.reverted) {
      tokenName = nameResult.value;
    }
    
    let decimalsResult = tokenContract.try_decimals();
    if (!decimalsResult.reverted) {
      tokenDecimals = decimalsResult.value;
    }
    
    token.symbol = tokenSymbol;
    token.name = tokenName;
    token.decimals = tokenDecimals;
    token.save();
  }
  
  return token as Token;
}

export function createProtocol(): Protocol {
  let protocol = new Protocol('uniswap-v4-lending-hook');
  protocol.name = 'Uniswap V4 Lending Hook';
  protocol.totalValueLockedUSD = ZERO_BI;
  protocol.cumulativeFeeUSD = ZERO_BI;
  protocol.save();
  return protocol;
}

export function updateProtocolTVL(protocol: Protocol, amountUSD: BigInt, isDeposit: boolean): void {
  if (isDeposit) {
    protocol.totalValueLockedUSD = protocol.totalValueLockedUSD.plus(amountUSD);
  } else {
    protocol.totalValueLockedUSD = protocol.totalValueLockedUSD.minus(amountUSD);
  }
  protocol.save();
}

export function updateProtocolFees(protocol: Protocol, feeUSD: BigInt): void {
  protocol.cumulativeFeeUSD = protocol.cumulativeFeeUSD.plus(feeUSD);
  protocol.save();
}

export function updatePoolTVL(pool: Pool, amountUSD: BigInt, isDeposit: boolean): void {
  if (isDeposit) {
    pool.totalValueLockedUSD = pool.totalValueLockedUSD.plus(amountUSD);
  } else {
    pool.totalValueLockedUSD = pool.totalValueLockedUSD.minus(amountUSD);
  }
  pool.save();
}

export function updatePoolFees(pool: Pool, feeUSD: BigInt): void {
  pool.cumulativeSwapFeeUSD = pool.cumulativeSwapFeeUSD.plus(feeUSD);
  pool.save();
}
