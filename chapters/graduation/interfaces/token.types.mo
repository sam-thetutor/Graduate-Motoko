// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  public type Result = { #ok; #err : Text };
  public type Actor = actor {
    balanceOf : shared query Principal -> async Nat;
    balanceOfArray : shared query [Principal] -> async [Nat];
    burn : shared (Principal, Nat) -> async Result;
    mint : shared (Principal, Nat) -> async Result;
    tokenName : shared query () -> async Text;
    tokenSymbol : shared query () -> async Text;
    totalSupply : shared query () -> async Nat;
    transfer : shared (Principal, Principal, Nat) -> async Result;
  }
}