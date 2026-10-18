// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {OgClubToken} from "../src/OgClubToken.sol";

/// @notice Edge cases the main suite does not pin: allowance overwrite, zero-amount and
///         self-directed transferFrom, receivers at zero, and repeated deployments.
contract OgClubTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    OgClubToken internal token;

    function setUp() public {
        vm.prank(deployer);
        token = new OgClubToken();
    }

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(deployer);
        token.approve(bob, 10 ether);
        token.approve(bob, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(deployer, bob), 3 ether);
    }

    function test_approveToZeroRevokes() public {
        vm.prank(deployer);
        token.approve(bob, 10 ether);
        vm.prank(deployer);
        token.approve(bob, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromZeroAmountNeedsNoAllowance() public {
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, 0));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromOwnFundsStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
    }

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(deployer);
        token.approve(bob, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(bob);
        token.transferFrom(deployer, address(0), 1 ether);
        assertEq(token.allowance(deployer, bob), 1 ether, "a failed transferFrom must not spend allowance");
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_allowanceExactlySpentDropsToZero() public {
        vm.prank(deployer);
        token.approve(bob, 2 ether);
        vm.prank(bob);
        token.transferFrom(deployer, alice, 2 ether);
        assertEq(token.allowance(deployer, bob), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
    }

    function test_oneWeiTransfer() public {
        vm.prank(deployer);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_eachDeploymentIsIndependentAndMintsOnce() public {
        vm.prank(alice);
        OgClubToken second = new OgClubToken();
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(second.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY, "a second deployment must not touch the first");
        assertEq(token.balanceOf(alice), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactAllowance(address spender, uint256 amount) public {
        spender = address(uint160(bound(uint160(spender), 1, type(uint160).max)));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), 0, "approving moves nothing");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_chainOfTransfersConserves(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        vm.prank(deployer);
        token.transfer(alice, a);
        vm.prank(alice);
        token.transfer(bob, b);
        assertEq(token.balanceOf(deployer), SUPPLY - a);
        assertEq(token.balanceOf(alice), a - b);
        assertEq(token.balanceOf(bob), b);
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }
}
