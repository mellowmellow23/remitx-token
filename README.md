# RemitX Token (RMX)

![CI](https://github.com/mellowmellow23/remitx-token/actions/workflows/test.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)
![Tests](https://img.shields.io/badge/tests-18%20passing-brightgreen)

Global remittance fees heavily tax cross-border payments, disproportionately
affecting individuals sending money to developing nations. Traditional financial
rails lack transparent, automated mechanisms to reward loyal users or offset
these high operational costs.

RemitX Token (RMX) is an EIP-20 compliant reward token designed to solve this
via on-chain programmatic incentives:

- **Gasless approvals:** Utilizes EIP-2612 `permit` signatures, allowing users
  to interact with DeFi protocols without holding native ETH for approval gas.
- **Economic scarcity:** A hardcoded `MAX_SUPPLY` of 50M tokens ensures
  predictable tokenomics and prevents arbitrary inflation by the protocol owner.
- **On-chain redemption:** A native `redeemForDiscount` burn mechanism that
  allows users to provably destroy tokens in exchange for remittance fee
  reductions, emitting indexable on-chain events.

---

## Contract architecture

| Parent contract | Role |
|---|---|
| `ERC20` | Base fungible token — transfers, balances, allowances (EIP-20) |
| `ERC20Burnable` | Lets token holders destroy their own tokens, reducing total supply |
| `ERC20Permit` | Adds EIP-2612 gasless approvals via off-chain signatures |
| `Ownable` | Restricts minting to the trusted platform transfer agent only |

---

## Security & testing

Built test-first using Foundry. The suite covers 18 tests across unit,
edge case, exploit simulation, and property-based fuzz categories.

| Category | Count | What it proves |
|---|---|---|
| Unit tests | 14 | Correct behaviour for known inputs |
| Fuzz tests | 4 | Invariants hold across 256 random inputs each |
| **Total** | **18** | **18 / 18 passing** |

**Key security properties tested:**

- `MAX_SUPPLY` cap enforced across 256+ random mint amounts via fuzzing
- Signature replay attack on `permit()` — stale nonce returns `ERC2612InvalidSigner`
- Expired permit deadline — reverts with `ERC2612ExpiredSignature`
- `renounceOwnership()` permanently disabled — cannot accidentally brick minting
- Zero-address and zero-amount guards on all state-changing functions

See [`TEST_REPORT.md`](./TEST_REPORT.md) for the full coverage map and gas breakdown.

---

## EIP references

- [EIP-20: Token Standard](https://eips.ethereum.org/EIPS/eip-20)
- [EIP-2612: Permit Extension for ERC-20 Signed Approvals](https://eips.ethereum.org/EIPS/eip-2612)
- [EIP-165: Interface Detection](https://eips.ethereum.org/EIPS/eip-165)

---

## Live deployment

| | |
|---|---|
| Network | Sepolia Testnet |
| Contract address | `0x04704a2d38378Cc084AF2604d7211C531b71163b` |
| Verified source | [View on Etherscan](https://sepolia.etherscan.io/address/0x04704a2d38378Cc084AF2604d7211C531b71163b) |

---

## What you can build on top of this

This contract is a production-ready base layer. Examples of what clients
integrate on top:

- A **Node.js / Express backend** that listens to a Wise or Stripe webhook
  confirming a remittance transfer, then calls `mint()` to reward the sender
  with RMX automatically.
- A **React dashboard** (see Task 10 — RemitX Portal) where users connect
  their wallet, view their RMX balance, and call `redeemForDiscount()` to
  claim a fee reduction on their next transfer.
- A **subgraph on The Graph** that indexes `DiscountRedeemed` events so the
  platform can display a user's full redemption history off-chain.

---

## How to run locally

**Prerequisites:** Foundry installed via WSL2 on Windows, or natively on
macOS / Linux. See [Foundry docs](https://book.getfoundry.sh/getting-started/installation).

```bash
# 1. Clone the repo
git clone https://github.com/mellowmellow23/remitx-token.git
cd remitx-token

# 2. Install dependencies
forge install

# 3. Run the full test suite
forge test -v

# 4. Run fuzz tests only
forge test --match-test Fuzz -v

# 5. Check the gas snapshot
forge snapshot

# 6. Generate a gas report
forge test --gas-report
```

Expected output:
