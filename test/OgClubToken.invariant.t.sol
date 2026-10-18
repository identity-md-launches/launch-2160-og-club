// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {OgClubToken} from "../src/OgClubToken.sol";

/// @notice Drives the token with random transfers, approvals and transferFroms between a fixed set
///         of actors, including calls that must fail. Keeps its own book of what every balance and
///         allowance should be, computed from the ERC-20 rules rather than read back from the token.
contract OgClubHandler is Test {
    OgClubToken public immutable token;
    address[] public actors;

    /// @dev Expected balances and allowances, maintained independently of the token.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostSuccessfulMoves;
    uint256 public ghostRejectedCalls;
    /// @dev Set if a call that the rules say must fail succeeded, or one that must succeed failed.
    bool public ghostRuleBroken;

    constructor(OgClubToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        // actors[0] is the deployer, which holds the whole supply at the start.
        ghostBalance[actors_[0]] = token_.totalSupply();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Amounts sometimes exceed the sender's balance so the failure path is exercised too.
    function _amount(uint256 raw, uint256 held) internal pure returns (uint256) {
        if (raw % 5 == 0) return bound(raw, held, held + 1e27);
        return bound(raw, 0, held);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        uint256 amount = _amount(rawAmount, held);

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok || amount > held) ghostRuleBroken = true;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ++ghostSuccessfulMoves;
        } catch (bytes memory reason) {
            bytes memory expected =
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount);
            if (amount <= held || keccak256(reason) != keccak256(expected)) ghostRuleBroken = true;
            ++ghostRejectedCalls;
        }
    }

    function transferToZero(uint256 fromSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        uint256 amount = bound(rawAmount, 0, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            ghostRuleBroken = true; // a transfer to zero would be a burn
        } catch {
            ++ghostRejectedCalls;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        // Mix exact amounts, small amounts and the infinite allowance.
        if (amount % 7 == 0) amount = type(uint256).max;
        else amount = bound(amount, 0, 2e27);

        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            if (!ok) ghostRuleBroken = true;
            ghostAllowance[owner][spender] = amount;
        } catch {
            ghostRuleBroken = true;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = held < allowed ? held : allowed;
        uint256 amount = _amount(rawAmount, cap);

        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            if (!ok || amount > held || amount > allowed) ghostRuleBroken = true;
            if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ++ghostSuccessfulMoves;
        } catch (bytes memory reason) {
            // OpenZeppelin checks the allowance before the balance.
            bytes memory expected = amount > allowed
                ? abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
                : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount);
            if ((amount <= allowed && amount <= held) || keccak256(reason) != keccak256(expected)) {
                ghostRuleBroken = true;
            }
            ++ghostRejectedCalls;
        }
    }

    /// @dev A stranger outside the actor set tries privileged-looking selectors; none may exist.
    function strangerPokes(uint256 selectorSeed, uint256 amount) external {
        bytes4[6] memory selectors = [
            bytes4(keccak256("mint(address,uint256)")),
            bytes4(keccak256("burn(uint256)")),
            bytes4(keccak256("burnFrom(address,uint256)")),
            bytes4(keccak256("transferOwnership(address)")),
            bytes4(keccak256("pause()")),
            bytes4(keccak256("blacklist(address)"))
        ];
        address victim = _actor(amount);
        vm.prank(address(0xBAD));
        (bool ok,) = address(token).call(abi.encodeWithSelector(selectors[selectorSeed % 6], victim, amount));
        if (ok) ghostRuleBroken = true;
        ++ghostRejectedCalls;
    }
}

contract OgClubTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    OgClubToken internal token;
    OgClubHandler internal handler;
    address[] internal actors;

    function setUp() public {
        address deployer = makeAddr("deployer");
        actors.push(deployer);
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("pool"));

        vm.prank(deployer);
        token = new OgClubToken();
        handler = new OgClubHandler(token, actors);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = OgClubHandler.transfer.selector;
        selectors[1] = OgClubHandler.transferToZero.selector;
        selectors[2] = OgClubHandler.approve.selector;
        selectors[3] = OgClubHandler.transferFrom.selector;
        selectors[4] = OgClubHandler.strangerPokes.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "tokens left the actor set or were created");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0xBAD)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesMatchGhostBook() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allowancesMatchGhostBook() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.ghostAllowance(actors[i], actors[j]));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_everyCallFollowedTheRules() public view {
        assertFalse(handler.ghostRuleBroken());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_tokenHoldsNoEther() public view {
        assertEq(address(token).balance, 0);
    }
}
