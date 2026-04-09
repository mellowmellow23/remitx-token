# RemitX Token (RMX)

Global remittance fees heavily tax cross-border payments, disproportionately affecting individuals sending money to developing nations. Traditional financial rails lack transparent, automated mechanisms to reward loyal users or offset these high operational costs. 

RemitX Token (RMX) is an EIP-20 compliant reward token designed to solve this via on-chain programmatic incentives:
* **Gasless Approvals:** Utilizes EIP-2612 `permit` signatures, allowing users to interact with DeFi protocols without holding native ETH for approval gas.
* **Economic Scarcity:** A hardcoded `MAX_SUPPLY` of 50M tokens ensures predictable tokenomics and prevents arbitrary inflation by the protocol owner.
* **On-Chain Redemption:** A native `redeemForDiscount` burn mechanism that allows users to provably destroy tokens in exchange for remittance fee reductions, emitting indexable events for webhooks.

### Contract Architecture
* **`ERC20`**: The base standard implementation for fungible token transfers and balances.
* **`ERC20Burnable`**: An extension enabling token holders to securely destroy their own tokens, shrinking the total supply.
* **`ERC20Permit`**: An extension providing EIP-2612 capabilities for off-chain, signature-based allowance modifications.
* **`Ownable`**: An access control module ensuring only the platform's trusted transfer agent can mint new rewards.

### EIP References
* [EIP-20: Token Standard](https://eips.ethereum.org/EIPS/eip-20)
* [EIP-2612: Permit Extension for ERC-20 Signed Approvals](https://eips.ethereum.org/EIPS/eip-2612)

### How to Run Locally

1. Install dependencies:
   ```bash
   forge install