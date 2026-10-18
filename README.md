# Og Club (OG)

A fixed-supply ERC-20 token for the IMD custom-token launch on Ethereum mainnet.

| Property        | Value                                                            |
| --------------- | ---------------------------------------------------------------- |
| Contract        | `OgClubToken` (`src/OgClubToken.sol`)                            |
| Name            | `Og Club`                                                        |
| Symbol          | `OG`                                                             |
| Decimals        | 18                                                               |
| Total supply    | 1,000,000,000 OG = `1000000000000000000000000000` minor units    |
| Minting         | Once, in the constructor, all of it to `msg.sender` (the deployer) |
| Constructor args| None                                                             |
| Owner / admin   | None                                                             |

## Behaviour

`OgClubToken` inherits OpenZeppelin v5.4.0 `ERC20` and adds nothing but the constructor mint.
Concretely:

- **Supply is fixed.** `TOTAL_SUPPLY` (1e27) is minted exactly once to the deployer. There is no
  `mint`, `owner`, minter role, upgrade path, proxy or initializer. `totalSupply()` can never rise.
- **Transfers are exact.** No fee, tax, reflection, burn-on-transfer, hook or allowlist. Every
  `transfer` / `transferFrom` moves precisely the amount requested, so the launch flows (factory to
  distributor, distributor to claimants, pool seed, swaps through the Uniswap v4 PoolManager) arrive
  whole. Nothing is exempted because nothing needs exempting.
- **No privileged hand.** There is no pause, blocklist, freeze, lock, seize or `burnFrom`. Only a
  holder, or a spender the holder approved, can move a holder's balance.
- **Standard failures.** Transfers above balance, `transferFrom` above allowance, and transfers or
  approvals involving the zero address revert with OpenZeppelin's ERC-6093 custom errors
  (`ERC20InsufficientBalance`, `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`,
  `ERC20InvalidSpender`). The contract has no `receive` or `fallback`, so plain ETH sent to it reverts.
- **No dangerous opcodes.** The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`
  (asserted by a test that scans the deployed bytecode).

## Deployment parameters

The token takes **no constructor arguments**. The IMD ProjectFactory deploys the attested bytecode
through `launchCustom`; because the constructor mints to `msg.sender`, the factory receives the
entire supply in the creation transaction and pays it out. The constructor calls no other contract
and reads no external state, so it runs on an empty chain.

Values the launch supplies (recorded by the manifest step, not by this repository):

| Setting                 | Value                                                      |
| ----------------------- | ---------------------------------------------------------- |
| Chain                   | Ethereum mainnet (chain id 1)                              |
| `token.contract`        | `OgClubToken`                                              |
| `token.totalSupply`     | `1000000000000000000000000000`                             |
| `token.decimals`        | `18`                                                       |
| `token.constructorArgs` | `[]`                                                       |
| Paired currency         | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`          |
| Pool fee / tick spacing | 12500 (1.25%) / 60                                         |
| Economics               | `poolBps` 8000, `initialMarketCapWei` 2,500 IMD, remainder to `0x612a9bb008e16ef2d24f41dae9fc661831d93367` |

How the supply is paid out by the factory (none of it is encoded in the token):

| Share | Destination                                    |
| ----- | ---------------------------------------------- |
| 10%   | Launch MerkleDistributor (swarm contributors)  |
| 80%   | Single-sided Uniswap v4 pool, paired with IMD  |
| 10%   | `economics.remainderTo` (the requester)        |

Nothing in this repository deploys, broadcasts or signs anything. `script/DeployOgClubToken.s.sol`
exists for local and fork rehearsals only: its `deploy()` function is called directly by the tests,
and `run()` reads nothing from the environment.

## After launch

There is nothing to configure. The token has no owner-settable values, no external dependencies and
no post-deployment steps.

## Assumptions

- The requester wants a plain, immutable ERC-20: the brief asks for a name, symbol and fixed supply
  minted to the deployer, and nothing else. No tax, vesting, burn, governance or admin features were
  added because none were requested; adding any would have changed the launch flows.
- "Deployer" is `msg.sender` of the creation transaction. At launch that is the ProjectFactory, which
  is what the launch requires. In a local rehearsal it is whoever runs the script.
- 18 decimals is both the brief's requirement and the ERC-20 default, so `decimals()` is not
  overridden.

## Operational responsibilities

- **Requester**: receives the remainder share at `economics.remainderTo` and is responsible for that
  wallet's key. The token offers no recovery, freeze or clawback, so a lost key or a mistaken transfer
  cannot be undone by anyone.
- **IMD deployer / factory**: performs the launch from the attested bytecode, forwards the swarm share
  to the distributor, seeds the pool and forwards the remainder. Explorer verification of the deployed
  source is the deployer's step, not this repository's.
- **Holders**: ordinary ERC-20 custody. Approvals granted to third parties are the holder's
  responsibility; the token does not expire or cap them.
- **No one** can mint, pause, blocklist or upgrade. This is a deliberate trust property, not an
  omission: there is no admin to compromise.

## Security notes

Checked against the eth-security checklist supplied with the task:

- Reentrancy: no external calls in the token beyond ERC-20 storage updates; nothing to re-enter.
- Access control: no privileged functions exist; the test `test_privilegedSelectorsAreAbsent`
  asserts 22 common admin selectors revert for both a stranger and the deployer.
- Arithmetic: Solidity 0.8.26 checked arithmetic plus OpenZeppelin's audited ERC20.
- Supply growth: impossible after construction (no mint path, no proxy, no `DELEGATECALL`).
- Tools run: `forge build`, `forge test` (including fuzz with the verifier's seed), `forge fmt --check`.
  Slither and Mythril were not available in this environment and did not run.

Tests passing are not an audit. The contract is small and uses an audited base, but an independent
adversarial review before release remains good practice.

## Building and testing

```
forge build
forge test
forge fmt --check
```

`foundry.toml` pins `solc = "0.8.26"`, `bytecode_hash = "none"` and `cbor_metadata = false` so the
built bytecode is reproducible without a metadata hash, as the launch requires. `ffi` is off and no
filesystem permissions are granted. Tests read no environment variables and pass in any order.

## Dependencies (vendored as plain files, no submodules)

- `lib/forge-std` — foundry-rs/forge-std v1.11.0 (`src/` plus licences).
- `lib/openzeppelin-contracts` — OpenZeppelin Contracts v5.4.0, only the files `ERC20` needs:
  `token/ERC20/ERC20.sol`, `token/ERC20/IERC20.sol`, `token/ERC20/extensions/IERC20Metadata.sol`,
  `utils/Context.sol`, `interfaces/draft-IERC6093.sol`, plus the MIT licence.

Remappings are in `remappings.txt`.
