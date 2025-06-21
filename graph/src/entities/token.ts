import { BigInt, BigDecimal, Address } from "@graphprotocol/graph-ts";
import { Token } from "../../generated/schema";
import { ERC20 } from "../../generated/HookV1/ERC20";
import { getOrCreateProtocol } from "./protocol";

export function getOrCreateToken(tokenAddress: string, tokenPriceUSD: BigDecimal): Token {
  let address = Address.fromString(tokenAddress);
  let token = Token.load(address.toHexString());

  if (token === null) {
    token = new Token(address.toHexString());
    let tokenContract = ERC20.bind(address);

    // Try to load token data - handle potential contract call failures
    let tokenSymbol = "";
    let tokenName = "";
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
    token.lastPriceUSD = tokenPriceUSD;
    token.protocol = getOrCreateProtocol().id;
    token.save();
  }

  return token as Token;
}

// todo: update to handle non stable coins
export function convertTokenToUSD(
  token: Token,
  amount: BigInt
//   tokenPriceUSD = BigDecimal.fromString("1")
): BigDecimal {
  let amountBD = new BigDecimal(amount);
  let tokenDecimalsBD = new BigDecimal(
    BigInt.fromI32(10).pow(u8(token.decimals))
  );
  let amountInUSD = amountBD.div(tokenDecimalsBD).times(token.lastPriceUSD);

  return amountInUSD;
}
