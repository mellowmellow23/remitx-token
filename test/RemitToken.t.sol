// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =============================================================================
// RemitToken — Full Test Suite
// =============================================================================
// Forge version : 0.2.0 (or later)
// Solidity      : ^0.8.20
// Run all tests : forge test -v
// Run with gas  : forge test --gas-report
// Run fuzz only : forge test --match-test Fuzz -v
//
// Test results (captured 2025):
// ✓ testFuzz_MintRespectsSupplyCap           runs: 256
// ✓ testFuzz_MintToAnyValidAddress           runs: 256
// ✓ testFuzz_PartialBurnLeavesCorrectBalance runs: 256
// ✓ testFuzz_UserCanAlwaysBurnFullBalance    runs: 256
// ✓ test_InitialSupplyIsZero                 gas: 7922
// ✓ test_MintCannotExceedMaxSupply           gas: 69410
// ✓ test_MintRevertsOnZeroAddress            gas: 14327
// ✓ test_MintRevertsOnZeroAmount             gas: 16462
// ✓ test_NonOwnerCannotMint                  gas: 15342
// ✓ test_OwnerCanMint                        gas: 66233
// ✓ test_OwnershipTransfer                   gas: 78180
// ✓ test_PermitExpiredDeadlineReverts        gas: 26382
// ✓ test_PermitReplayAttackFails             gas: 87514
// ✓ test_PermitWorks                         gas: 77099
// ✓ test_RedeemRevertsOnInsufficientBalance  gas: 67499
// ✓ test_RedeemRevertsOnZeroAmount           gas: 65514
// ✓ test_RenounceOwnershipReverts            gas: 11092
// ✓ test_UserCanBurn                         gas: 75618
// Suite: 18 passed, 0 failed
//
// Fuzz configuration:
//   Default runs: 256. To increase, add to foundry.toml:
//   [fuzz]
//   runs = 1000
//
// =============================================================================
// Coverage map
// =============================================================================
// Function                | Unit tests | Fuzz tests | Notes
// ----------------------- | ---------- | ---------- | -------------------------
// mint()                  | 5          | 2          | cap, zero, address, auth
// redeemForDiscount()     | 3          | 2          | burn, zero, insufficient
// renounceOwnership()     | 1          | -          | permanently disabled
// transferOwnership()     | 1          | -          | full handoff
// permit()                | 3          | -          | happy path, expiry, replay
// =============================================================================
//
// Note on vm.expectRevert selector-only usage:
//   Some revert assertions use bare `.selector` instead of abi.encodeWithSelector.
//   This is intentional when one or more error arguments are not predictable at
//   test-write time (e.g. a recovered signer address from a stale EIP-712 signature).
//   Use abi.encodeWithSelector when you control all argument values and want the
//   tightest possible assertion. Use bare .selector when arguments are dynamic.
// =============================================================================

import {Test, console} from "forge-std/Test.sol";
import {RemitToken} from "../src/RemitToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RemitTokenTest is Test {
    RemitToken public token;

    address public owner;
    address public user;
    uint256 public ownerPrivateKey;

    /// @dev Redeclared here so vm.expectEmit can match against it.
    ///      Foundry requires the event to be in scope in the test contract.
    event DiscountRedeemed(address indexed user, uint256 amount);

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        user = makeAddr("user");

        // No vm.prank needed — owner is passed as a constructor argument,
        // msg.sender is not used for access control during deployment.
        token = new RemitToken(owner);
    }

    // =========================================================================
    // Initial state
    // =========================================================================

    /// @notice Proves that total supply starts at zero before any minting occurs.
    function test_InitialSupplyIsZero() public view {
        assertEq(token.totalSupply(), 0);
    }

    // =========================================================================
    // mint() — happy path
    // =========================================================================

    /// @notice Proves the owner can mint tokens and balances update correctly.
    /// @dev    Checks both balanceOf and totalSupply to confirm state is consistent.
    function test_OwnerCanMint() public {
        vm.prank(owner);
        token.mint(user, 1000 * 10 ** 18);

        assertEq(token.balanceOf(user), 1000 * 10 ** 18);
        assertEq(token.totalSupply(), 1000 * 10 ** 18);
    }

    /// @notice Proves the 50M economic cap is strictly enforced on-chain.
    /// @dev    First mint fills the cap exactly (must succeed), second mint
    ///         of 1 wei must revert with the custom error.
    function test_MintCannotExceedMaxSupply() public {
        vm.startPrank(owner);

        token.mint(user, token.MAX_SUPPLY());
        assertEq(token.totalSupply(), token.MAX_SUPPLY());

        vm.expectRevert(RemitToken.RemitToken__MaxSupplyExceeded.selector);
        token.mint(user, 1);

        vm.stopPrank();
    }

    // =========================================================================
    // mint() — revert cases
    // =========================================================================

    /// @notice Proves unauthorized accounts are blocked from minting.
    /// @dev    OpenZeppelin Ownable reverts with OwnableUnauthorizedAccount
    ///         when a non-owner calls an onlyOwner function.
    function test_NonOwnerCannotMint() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        token.mint(user, 1000 * 10 ** 18);
    }

    /// @notice Proves mint reverts when the recipient is the zero address.
    /// @dev    We enforce this explicitly in our own guard rather than relying
    ///         silently on OZ's internal _mint revert. Auditors expect this.
    function test_MintRevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RemitToken.RemitToken__ZeroAddress.selector);
        token.mint(address(0), 1000 * 10 ** 18);
    }

    /// @notice Proves mint reverts when amount is zero.
    /// @dev    Minting 0 tokens wastes gas and emits no meaningful state change.
    ///         The zero-amount guard catches this before _mint is ever called.
    function test_MintRevertsOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(RemitToken.RemitToken__ZeroAmount.selector);
        token.mint(user, 0);
    }

    // =========================================================================
    // redeemForDiscount() — happy path
    // =========================================================================

    /// @notice Proves a user can burn tokens and DiscountRedeemed is emitted correctly.
    /// @dev    vm.expectEmit parameters:
    ///           true  = check first indexed topic (user address)
    ///           false = no second indexed topic
    ///           false = no third indexed topic
    ///           true  = check non-indexed data (amount)
    ///         Asserts both balanceOf and totalSupply decrease — burning is
    ///         deflationary and permanently removes tokens from circulation.
    function test_UserCanBurn() public {
        vm.prank(owner);
        token.mint(user, 500 * 10 ** 18);

        vm.startPrank(user);
        vm.expectEmit(true, false, false, true);
        emit DiscountRedeemed(user, 100 * 10 ** 18);
        token.redeemForDiscount(100 * 10 ** 18);
        vm.stopPrank();

        assertEq(token.balanceOf(user), 400 * 10 ** 18);
        assertEq(token.totalSupply(), 400 * 10 ** 18);
    }

    // =========================================================================
    // redeemForDiscount() — revert cases
    // =========================================================================

    /// @notice Proves redeemForDiscount reverts when amount is zero.
    /// @dev    Burning 0 tokens is a no-op that wastes gas and emits a
    ///         misleading event. The zero-amount guard catches this early.
    function test_RedeemRevertsOnZeroAmount() public {
        vm.prank(owner);
        token.mint(user, 500 * 10 ** 18);

        vm.prank(user);
        vm.expectRevert(RemitToken.RemitToken__ZeroAmount.selector);
        token.redeemForDiscount(0);
    }

    /// @notice Proves redeemForDiscount reverts when the user burns more than their balance.
    /// @dev    We do not write our own balance check — ERC20Burnable.burn()
    ///         handles this internally and reverts with ERC20InsufficientBalance.
    ///         This test proves we correctly rely on OZ's battle-tested logic.
    function test_RedeemRevertsOnInsufficientBalance() public {
        vm.prank(owner);
        token.mint(user, 100 * 10 ** 18);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, 100 * 10 ** 18, 200 * 10 ** 18)
        );
        token.redeemForDiscount(200 * 10 ** 18);
    }

    // =========================================================================
    // Ownership
    // =========================================================================

    /// @notice Proves renounceOwnership is permanently disabled.
    /// @dev    Without this override, the owner could accidentally call
    ///         renounceOwnership() and permanently lock the mint function.
    ///         Overriding and reverting is the standard defensive pattern.
    function test_RenounceOwnershipReverts() public {
        vm.prank(owner);
        vm.expectRevert(RemitToken.RemitToken__RenounceNotAllowed.selector);
        token.renounceOwnership();
    }

    /// @notice Proves ownership transfers correctly end to end.
    /// @dev    After transferOwnership():
    ///           - old owner must be blocked from minting
    ///           - new owner must be able to mint
    ///         This tests the full Ownable handoff, not just the transfer call.
    function test_OwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        token.transferOwnership(newOwner);

        // Old owner should now be blocked
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        token.mint(user, 1000 * 10 ** 18);

        // New owner should be able to mint
        vm.prank(newOwner);
        token.mint(user, 1000 * 10 ** 18);
        assertEq(token.balanceOf(user), 1000 * 10 ** 18);
    }

    // =========================================================================
    // permit() — EIP-2612
    // =========================================================================

    /// @notice Proves an off-chain EIP-712 signature updates an on-chain allowance gaslessly.
    /// @dev    Flow:
    ///           1. Build the EIP-712 struct hash for the Permit type
    ///           2. Combine with the token's domain separator to form the digest
    ///           3. Sign the digest with the owner's private key (off-chain simulation)
    ///           4. Anyone submits the permit on-chain — spender pays gas, not owner
    ///           5. Verify allowance was set correctly
    ///         This is the core EIP-2612 gasless approval pattern used in DeFi.
    function test_PermitWorks() public {
        address spender = makeAddr("spender");
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                token.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        token.permit(owner, spender, amount, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), amount);
    }

    /// @notice Proves permit() reverts when the deadline has passed.
    /// @dev    This is a critical EIP-2612 security property — time-bound
    ///         signatures prevent old approvals from being submitted long after
    ///         the user intended to authorise them.
    ///         vm.warp() sets block.timestamp to any value, letting us simulate
    ///         time passing without waiting for real blocks.
    function test_PermitExpiredDeadlineReverts() public {
        address spender = makeAddr("spender");
        uint256 amount = 100 * 10 ** 18;

        // Set deadline to right now — valid at signing time
        uint256 deadline = block.timestamp;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                token.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Warp 1 second forward — deadline is now in the past.
        // vm.warp() lets us manipulate block.timestamp in tests without
        // waiting for real blocks to be mined.
        vm.warp(block.timestamp + 1);

        // ERC2612ExpiredSignature lives on ERC20Permit, not IERC20Errors.
        // We match the full selector + argument because the deadline value
        // is known and predictable here.
        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        token.permit(owner, spender, amount, deadline, v, r, s);
    }

    /// @notice Proves a valid permit signature cannot be replayed after the nonce is consumed.
    /// @dev    Each permit call increments the owner's nonce. The second submission
    ///         carries a stale nonce, so the recovered signer is a garbage address
    ///         that does not match the declared owner.
    ///
    ///         Why we use bare .selector here instead of abi.encodeWithSelector:
    ///         ERC2612InvalidSigner(recoveredSigner, expectedOwner) — the first
    ///         argument is the address recovered from the stale signature, which
    ///         is not predictable from test code. Matching the selector only is
    ///         correct and intentional. Using abi.encodeWithSelector with a wrong
    ///         address guess would cause a false failure, as seen in the error:
    ///         "ERC2612InvalidSigner(0xA4D6..., 0xe05f...) != ERC2612InvalidSigner(0xe05f..., 0xe05f...)"
    ///
    ///         This is the core replay-attack protection in EIP-2612. Without
    ///         nonces, anyone who observed a permit transaction on-chain could
    ///         resubmit it to drain approvals repeatedly.
    /// @notice Proves a valid permit signature cannot be replayed after the nonce is consumed.
    function test_PermitReplayAttackFails() public {
        address spender = makeAddr("spender");
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 days;

        // Capture nonce before first permit — will be 0
        uint256 nonceBefore = token.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                nonceBefore,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // First submission — must succeed and increment the nonce from 0 to 1
        token.permit(owner, spender, amount, deadline, v, r, s);
        assertEq(token.nonces(owner), nonceBefore + 1);

        // --- THE FIX ---
        // Dynamically calculate the garbage address the contract will recover
        // when it hashes the payload using the new, incremented nonce.
        bytes32 staleStructHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                token.nonces(owner), // The nonce is now 1
                deadline
            )
        );

        bytes32 staleDigest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), staleStructHash));

        // ecrecover with the stale digest but original V, R, S yields the garbage address
        address recoveredSigner = ecrecover(staleDigest, v, r, s);

        // Now we can strictly match the exact 68-byte custom error OpenZeppelin expects
        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, recoveredSigner, owner));
        token.permit(owner, spender, amount, deadline, v, r, s);
    }

    // =========================================================================
    // Fuzz tests
    // =========================================================================
    // How fuzz tests work in Foundry:
    //   - Any test function with parameters is automatically a fuzz test.
    //   - Foundry generates random values for those parameters on every run.
    //   - Default runs: 256. Increase in foundry.toml under [fuzz] runs = 1000.
    //   - If a run fails, Foundry prints the exact counterexample to reproduce it.
    //   - vm.assume(condition) skips inputs that violate a precondition without
    //     counting them as failures.
    // =========================================================================

    /// @notice Proves that for ANY valid amount within the cap, the owner can
    ///         always mint and totalSupply never exceeds MAX_SUPPLY.
    /// @dev    The fuzzer will try random uint256 values including 1 wei,
    ///         uint256 max, and values just below the supply cap.
    function testFuzz_MintRespectsSupplyCap(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= token.MAX_SUPPLY());

        vm.prank(owner);
        token.mint(user, amount);

        assertEq(token.balanceOf(user), amount);
        assertEq(token.totalSupply(), amount);
        assert(token.totalSupply() <= token.MAX_SUPPLY());
    }

    /// @notice Proves that for ANY amount a user holds, burning the full balance
    ///         always results in a zero balance and correct totalSupply reduction.
    function testFuzz_UserCanAlwaysBurnFullBalance(uint256 mintAmount) public {
        vm.assume(mintAmount > 0);
        vm.assume(mintAmount <= token.MAX_SUPPLY());

        vm.prank(owner);
        token.mint(user, mintAmount);

        vm.prank(user);
        token.redeemForDiscount(mintAmount);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.totalSupply(), 0);
    }

    /// @notice Proves that a partial burn always leaves the correct remaining
    ///         balance for any combination of mint and burn amounts.
    /// @dev    This catches any integer underflow or balance accounting errors
    ///         that fixed unit test values might miss.
    function testFuzz_PartialBurnLeavesCorrectBalance(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount > 0);
        vm.assume(mintAmount <= token.MAX_SUPPLY());
        vm.assume(burnAmount > 0);
        vm.assume(burnAmount < mintAmount);

        vm.prank(owner);
        token.mint(user, mintAmount);

        vm.prank(user);
        token.redeemForDiscount(burnAmount);

        assertEq(token.balanceOf(user), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    /// @notice Proves minting to ANY valid address works correctly —
    ///         not just the hardcoded `user` address in unit tests.
    /// @dev    Filters out address(0) which is a separate revert case.
    function testFuzz_MintToAnyValidAddress(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= token.MAX_SUPPLY());

        vm.prank(owner);
        token.mint(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
    }
}
