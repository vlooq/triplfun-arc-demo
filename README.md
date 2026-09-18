# Triplfun — Arc mainnet demo

Triplfun is an Arc-native market launch application. Creators can launch
fixed-supply tokens, open markets through Uniswap v4, and configure transparent
fee routes for creators, token holders, and NFT communities.

This repository is a deliberately limited public technical snapshot prepared
for the Arc Microgrants program. It is not the private Triplfun product
repository and does not contain operational signing tools, private assets,
deployment packages, infrastructure credentials, or the complete application.

## Live evidence

- Application: [tripl.fun](https://tripl.fun)
- Network: Arc mainnet, chain ID `5042`
- Public analytics: [tripl.fun/api/v4/analytics](https://tripl.fun/api/v4/analytics)
- Deployment addresses: [`deployment.json`](deployment.json)

Run the read-only verifier with Node 22 or newer:

```sh
npm run verify
```

It checks the Arc chain ID, deployed bytecode, public runtime bindings, V5
factory launch count, and the non-stale public analytics response. It does not
request a wallet, sign a transaction, or mutate onchain state.

## NFT-community thesis

NFT communities already have distribution, identity, and shared ownership, but
their revenue programs are often manual or custodial. Triplfun lets a market
commit an immutable NFT eligibility snapshot and route a disclosed part of its
trading fee to a pull-based reward contract.

The intended onboarding loop is simple:

1. A community creates a market on Arc.
2. Its eligible NFT set is committed publicly.
3. Trading fees accumulate in the community's selected quote asset.
4. Eligible holders discover a claim and come to Arc to use it.

The isolated reward contract included here demonstrates fixed-snapshot,
equal-per-NFT accounting and current-owner claims. A public community campaign
and cross-chain ownership proofs are next milestones, not claims of completed
production usage.

## Current state

Triplfun is live on Arc mainnet with public launch, trading, fee, and NFT mint
receipts. The latest V5 contracts add fixed collection snapshots and collection
reward accounting. The first externally partnered NFT-community campaign has
not yet launched.

The contracts and product remain experimental and unaudited. Nothing in this
repository promises returns, minimum distributions, liquidity, or continued
market value.

## Repository contents

- `scripts/verify-live.mjs` — dependency-free read-only production verifier.
- `deployment.json` — public Arc deployment identities.
- `src/TriplV5CollectionRewards.sol` — isolated NFT reward accounting source.
- `docs/ARCHITECTURE.md` — system and trust boundaries.
- `docs/ARC_MICROGRANT.md` — grant narrative and proposed milestone.

## License

The files in this limited repository are released under the MIT License. The
private Triplfun product repository, brand assets, and unpublished material are
not licensed or published by this repository.

