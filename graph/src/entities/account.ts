import { Account } from "../../generated/schema";
import { Deposit1 as DepositEvent } from "../../generated/HookV1/HookV1";

export function getOrCreateAccount(address: string): Account {
  let account = Account.load(address);
  if (account === null) {
    account = new Account(address);
    account.save();
  }
  return account;
}
