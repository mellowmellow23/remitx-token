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
// ✓ test_InitialSupplyIsZero              gas: 7967
// ✓ test_MintCannotExceedMaxSupply        gas: 69433
// ✓ test_MintRevertsOnZeroAddress         gas: 14305
// ✓ test_MintRevertsOnZeroAmount          gas: 16485
// ✓ test_NonOwnerCannotMint               gas: 15320
// ✓ test_OwnerCanMint                     gas: 66211
// ✓ test_PermitWorks                      gas: 77143
// ✓ test_RedeemRevertsOnInsufficientBal   gas: 67477
// ✓ test_RedeemRevertsOnZeroAmount        gas: 65470
// ✓ test_RenounceOwnershipReverts         gas: 11092
// ✓ test_UserCanBurn                      gas: 75639
// Suite: 11 passed, 0 failed — 16.37ms
//
// Fuzz tests use Foundry's built-in fuzzer (default 256 runs per test).
// To increase runs, set in foundry.toml:
//   [fuzz]
//   runs = 1000
// =============================================================================

import {Test, console} from "forge-std/Test.sol";
import {RemitToken} from "../src/RemitToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RemitTokenTest is Test {

    RemitToken public token;

    address public owner;
    address public user;
    uint256 public ownerPrivateKey;

    /// @dev Redeclared here so vm.expectEmit can match against it.
    event DiscountRedeemed(address indexed user, uint256 amount);

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        user = makeAddr("user");

        // No vm.prank needed — owner is passed as a constructor argument.
        token = new RemitToken(owner);
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    // Proves that the total supply starts at zero before any minting occurs.
    function test_InitialSupplyIsZero() public view {
        assertEq(token.totalSupply(), 0);
    }

    // -------------------------------------------------------------------------
    // Mint — happy path
    // -------------------------------------------------------------------------

    // Proves the owner can mint tokens and balances update correctly.
    function test_OwnerCanMint() public {
        vm.prank(owner);
        token.mint(user, 1000 * 10 ** 18);

        assertEq(token.balanceOf(user), 1000 * 10 ** 18);
        assertEq(token.totalSupply(), 1000 * 10 ** 18);
    }

    // Proves the 50M economic cap is strictly enforced on-chain.
    function test_MintCannotExceedMaxSupply() public {
        vm.startPrank(owner);

        token.mint(user, token.MAX_SUPPLY());
        assertEq(token.totalSupply(), token.MAX_SUPPLY());

        vm.expectRevert(RemitToken.RemitToken__MaxSupplyExceeded.selector);
        token.mint(user, 1);

        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Mint — revert cases
    // -------------------------------------------------------------------------

    // Proves unauthorized accounts are blocked from minting.
    function test_NonOwnerCannotMint() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
        );
        token.mint(user, 1000 * 10 ** 18);
    }

    // Proves mint reverts on zero address recipient.
    function test_MintRevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RemitToken.RemitToken__ZeroAddress.selector);
        token.mint(address(0), 1000 * 10 ** 18);
    }

    // Proves mint reverts when amount is zero.
    function test_MintRevertsOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(RemitToken.RemitToken__ZeroAmount.selector);
        token.mint(user, 0);
    }

    // -------------------------------------------------------------------------
    // redeemForDiscount — happy path
    // -------------------------------------------------------------------------

    // Proves a user can burn tokens and the DiscountRedeemed event is emitted.
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

    // -------------------------------------------------------------------------
    // redeemForDiscount — revert cases
    // -------------------------------------------------------------------------

    // Proves redeemForDiscount reverts on zero amount.
    function test_RedeemRevertsOnZeroAmount() public {
        vm.prank(owner);
        token.mint(user, 500 * 10 ** 18);

        vm.prank(user);
        vm.expectRevert(RemitToken.RemitToken__ZeroAmount.selector);
        token.redeemForDiscount(0);
    }

    // Proves redeemForDiscount reverts when user burns more than their balance.
    function test_RedeemRevertsOnInsufficientBalance() public {
        vm.prank(owner);
        token.mint(user, 100 * 10 ** 18);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                user,
                100 * 10 ** 18,
                200 * 10 ** 18
            )
        );
        token.redeemForDiscount(200 * 10 ** 18);
    }

    // -------------------------------------------------------------------------
    // Ownership
    // -------------------------------------------------------------------------

    // Proves renounceOwnership is permanently disabled.
    function test_RenounceOwnershipReverts() public {
        vm.prank(owner);
        vm.expectRevert(RemitToken.RemitToken__RenounceNotAllowed.selector);
        token.renounceOwnership();
    }

    // -------------------------------------------------------------------------
    // EIP-2612 permit
    // -------------------------------------------------------------------------

    // Proves an off-chain EIP-712 signature updates an on-chain allowance gaslessly.
    function test_PermitWorks() public {
        address spender = makeAddr("spender");
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                spender,
                amount,
                token.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        token.permit(owner, spender, amount, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), amount);
    }

    // =========================================================================
    // Fuzz tests
    // =========================================================================
    // How fuzz tests work in Foundry:
    //   - Any test function with parameters is automatically treated as a fuzz test.
    //   - Foundry generates random values for those parameters on every run.
    //   - Default runs: 256. Set higher in foundry.toml under [fuzz] runs = 1000.
    //   - If a fuzz run finds a failure, Foundry prints the exact input that broke
    //     it so you can reproduce it — this is called a counterexample.
    //   - vm.assume(condition) tells the fuzzer to skip inputs that violate a
    //     precondition, rather than counting them as failures.
    // =========================================================================

    // Proves that for ANY valid amount within the cap, the owner can always mint
    // and the total supply never exceeds MAX_SUPPLY.
    // The fuzzer will throw random uint256 values at `amount` — including 1 wei,
    // uint256 max, and everything in between.
    function testFuzz_MintRespectsSupplyCap(uint256 amount) public {
        // Skip amounts that are zero (separate revert case) or exceed the cap.
        // vm.assume tells the fuzzer: "if this condition is false, discard this
        // input and try another — do not count it as a failure."
        vm.assume(amount > 0);
        vm.assume(amount <= token.MAX_SUPPLY());

        vm.prank(owner);
        token.mint(user, amount);

        // For every valid input the fuzzer tries, these must always hold.
        assertEq(token.balanceOf(user), amount);
        assertEq(token.totalSupply(), amount);
        assert(token.totalSupply() <= token.MAX_SUPPLY());
    }

    // Proves that for ANY amount a user holds, burning exactly that amount
    // always results in a zero balance and correct totalSupply reduction.
    function testFuzz_UserCanAlwaysBurnFullBalance(uint256 mintAmount) public {
        vm.assume(mintAmount > 0);
        vm.assume(mintAmount <= token.MAX_SUPPLY());

        vm.prank(owner);
        token.mint(user, mintAmount);

        // User burns their entire balance — should always succeed
        vm.prank(user);
        token.redeemForDiscount(mintAmount);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.totalSupply(), 0);
    }

    // Proves that a partial burn always leaves the correct remaining balance,
    // for any combination of mint amount and burn amount.
    function testFuzz_PartialBurnLeavesCorrectBalance(
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        // burnAmount must be less than mintAmount for a partial burn,
        // and both must be non-zero and within the supply cap.
        vm.assume(mintAmount > 0);
        vm.assume(mintAmount <= token.MAX_SUPPLY());
        vm.assume(burnAmount > 0);
        vm.assume(burnAmount < mintAmount);

        vm.prank(owner);
        token.mint(user, mintAmount);

        vm.prank(user);
        token.redeemForDiscount(burnAmount);

        // The remaining balance must always equal exactly mintAmount - burnAmount.
        // This catches any integer underflow or accounting errors.
        assertEq(token.balanceOf(user), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    // Proves that minting to ANY non-zero, non-zero-address recipient always
    // works correctly — not just the `user` address we hardcoded in unit tests.
    function testFuzz_MintToAnyValidAddress(address recipient, uint256 amount) public {
        // Filter out the two addresses that should always revert
        vm.assume(recipient != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= token.MAX_SUPPLY());

        vm.prank(owner);
        token.mint(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
    }
}