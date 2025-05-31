import { Bytes } from "@graphprotocol/graph-ts";
import { Account } from "../../generated/schema";


export function getAccount(address: string): Account | null {
  return Account.load(address);
}

export function createAccount(address: string, referralCode: Bytes | null): Account {
  const account = new Account(address);
  account.referralCodeUsed = referralCode;
  account.save();
  return account;
}
