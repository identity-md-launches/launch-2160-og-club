// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {OgClubToken} from "../src/OgClubToken.sol";
import {DeployOgClubToken} from "../script/DeployOgClubToken.s.sol";

/// @notice Stands in for the launch factory: deploys the token so it receives the supply, then pays
///         it out the way the factory does. Nothing in the token is special-cased for it.
contract FactoryStandIn {
    OgClubToken public token;

    function launch() external returns (OgClubToken) {
        token = new OgClubToken();
        return token;
    }

    function pay(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract OgClubTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    OgClubToken internal token;

    function setUp() public {
        vm.prank(deployer);
        token = new OgClubToken();
    }

    // ---------------------------------------------------------------- metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "Og Club");
        assertEq(token.symbol(), "OG");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "Og Club");
        assertEq(token.TOKEN_SYMBOL(), "OG");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyConstantIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.TOTAL_SUPPLY(), 1e27);
    }

    function test_constructorMintsWholeSupplyToDeployerOnce() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.recordLogs();
        vm.prank(deployer);
        OgClubToken fresh = new OgClubToken();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event: the mint");
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(address(uint160(uint256(logs[0].topics[1]))), address(0));
        assertEq(address(uint160(uint256(logs[0].topics[2]))), deployer);
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_supplyGoesToWhoeverDeploys_contractDeployer() public {
        FactoryStandIn factory = new FactoryStandIn();
        OgClubToken launched = factory.launch();
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(tx.origin), 0);
    }

    function test_deployScriptFunctionMintsToItsCaller() public {
        DeployOgClubToken script = new DeployOgClubToken();
        OgClubToken deployed = script.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(script)), SUPPLY);
        assertEq(deployed.name(), "Og Club");
        assertEq(deployed.symbol(), "OG");
    }

    // ---------------------------------------------------------------- transfers: success

    function test_transferMovesExactAmountAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 1_000 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1_000 ether));
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(deployer);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        token.transfer(deployer, 5 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_approveAndTransferFrom() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(alice, bob, 60 ether);
        vm.prank(alice);
        assertTrue(token.approve(bob, 60 ether));
        assertEq(token.allowance(alice, bob), 60 ether);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, stranger, 40 ether));
        assertEq(token.balanceOf(stranger), 40 ether);
        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.allowance(alice, bob), 20 ether);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1 ether);
        assertEq(token.allowance(deployer, bob), type(uint256).max);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    // ---------------------------------------------------------------- transfers: failure

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 10 ether + 1)
        );
        vm.prank(alice);
        token.transfer(bob, 10 ether + 1);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromEmptyAccountReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, stranger, 0, 1));
        vm.prank(stranger);
        token.transfer(bob, 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1 ether);
        assertEq(token.totalSupply(), SUPPLY, "a transfer to zero must not burn");
    }

    function test_transferFromWithoutAllowanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1 ether));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromAboveAllowanceReverts() public {
        vm.prank(deployer);
        token.approve(bob, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 5 ether, 5 ether + 1)
        );
        vm.prank(bob);
        token.transferFrom(deployer, bob, 5 ether + 1);
        assertEq(token.allowance(deployer, bob), 5 ether);
    }

    function test_transferFromAboveOwnerBalanceReverts() public {
        vm.prank(deployer);
        token.transfer(alice, 1 ether);
        vm.prank(alice);
        token.approve(bob, 2 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 2 ether));
        vm.prank(bob);
        token.transferFrom(alice, bob, 2 ether);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    // ---------------------------------------------------------------- no privileged powers

    /// @dev The token exposes no mint, owner, pause or blocklist surface at all. Every selector a
    ///      privileged token might answer must fall through to the (absent) fallback and revert.
    function test_privilegedSelectorsAreAbsent() public {
        string[22] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "setOwner(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "upgradeTo(address)",
            "initialize(address)",
            "pause()",
            "unpause()",
            "setMinter(address)",
            "blacklist(address)",
            "freeze(address)",
            "setBlacklist(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "seize(address)"
        ];
        address[2] memory callers = [stranger, deployer];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 i; i < signatures.length; ++i) {
                bytes memory data = abi.encodeWithSignature(signatures[i], callers[c], type(uint128).max);
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, signatures[i]);
            }
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(stranger), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_plainEtherIsRefused() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_deployerCannotMoveAHoldersBalanceWithoutAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 7 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 7 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 3 ether));
        assertEq(token.balanceOf(bob), 3 ether);
    }

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "EIP-170");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ---------------------------------------------------------------- launch flows arrive whole

    /// @dev The factory sends 10% to the distributor, the distributor pays a claimant, 80% goes to a
    ///      pool and the remainder to the requester. None of it may arrive short.
    function test_launchStyleFlowsArriveWhole() public {
        FactoryStandIn factory = new FactoryStandIn();
        OgClubToken launched = factory.launch();
        address distributor = makeAddr("distributor");
        address claimant = makeAddr("claimant");
        address pool = makeAddr("pool");
        address requester = makeAddr("requester");

        uint256 swarm = (SUPPLY * 1_000) / 10_000;
        uint256 poolShare = (SUPPLY * 8_000) / 10_000;
        uint256 remainder = SUPPLY - swarm - poolShare;

        assertTrue(factory.pay(distributor, swarm));
        assertTrue(factory.pay(pool, poolShare));
        assertTrue(factory.pay(requester, remainder));
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.balanceOf(requester), remainder);
        assertEq(launched.balanceOf(address(factory)), 0);

        vm.prank(distributor);
        assertTrue(launched.transfer(claimant, swarm));
        assertEq(launched.balanceOf(claimant), swarm);
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(to) + token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 attempt) public {
        held = bound(held, 0, SUPPLY - 1);
        attempt = bound(attempt, held + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, attempt));
        vm.prank(alice);
        token.transfer(bob, attempt);
        assertEq(token.balanceOf(alice), held);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 0, SUPPLY);
        spent = bound(spent, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(bob, allowed);
        if (spent > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, allowed, spent)
            );
            vm.prank(bob);
            token.transferFrom(deployer, alice, spent);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.allowance(deployer, bob), allowed);
        } else {
            vm.prank(bob);
            assertTrue(token.transferFrom(deployer, alice, spent));
            assertEq(token.balanceOf(alice), spent);
            assertEq(token.allowance(deployer, bob), allowed - spent);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
