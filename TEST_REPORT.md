# RemitToken — test report

## Summary
| Category       | Count | Status  |
|----------------|-------|---------|
| Unit tests     | 13    | passing |
| Fuzz tests     | 4     | passing |
| Total          | 17    | 17/17   |

## Fuzz configuration
- Runs per test: 256 (default)
- To increase: set `runs = 1000` in `foundry.toml` under `[fuzz]`

## What is tested and why

### mint()
Tests that the owner can mint, non-owners cannot, zero address is rejected,
zero amount is rejected, and the 50M supply cap is strictly enforced.
Fuzz tests verify these invariants hold for any random valid input.

### redeemForDiscount()
Tests that token holders can burn tokens to trigger the discount event,
zero amounts are rejected, and burning more than the held balance reverts
with OpenZeppelin's standard ERC20InsufficientBalance error.

### permit() — EIP-2612
Tests that a valid off-chain signature updates the on-chain allowance gaslessly,
and that expired signatures are rejected. The replay attack test proves a
consumed nonce cannot be reused.

### renounceOwnership()
Tests that the function is permanently disabled. Without this override,
the owner wallet could accidentally lock the mint function forever.

### transferOwnership()
Tests that ownership transfers correctly — the old owner loses mint rights
and the new owner gains them.

## How to run

```bash
# Run all tests
forge test -v

# Run with gas report
forge test --gas-report

# Run fuzz tests only
forge test --match-test Fuzz -v

# Run a specific test
forge test --match-test test_PermitWorks -v
```

## Gas snapshot
| Test                          | Gas    |
|-------------------------------|--------|
| test_OwnerCanMint             | 66,233 |
| test_UserCanBurn              | 75,596 |
| test_PermitWorks              | 77,165 |
| test_MintCannotExceedMaxSupply| 69,388 |