# Architecture and trust boundaries

## Live Arc path

Triplfun uses Arc as the settlement layer. The public runtime is bound to Arc
mainnet, canonical USDC, Arc's deployed Uniswap v4 PoolManager, and verified
factory, hook, and router addresses.

Market launches store fee configuration onchain. Trading fees are accounted for
separately from liquidity, creator credits, holder rewards, treasury revenue,
and NFT-related rewards. Claims are pull based; a trade does not loop over
holders.

## NFT-community rewards

The collection reward design commits:

- an ERC-721 collection address;
- a fixed token count and Merkle root;
- a manifest hash;
- a snapshot block and block hash; and
- a manifest URI.

Each eligible token receives an equal share of funded rewards. A claimant
provides the token ID, its snapshot index, and a Merkle proof. The current
contract then verifies `ownerOf(tokenId)` on the active chain before payment.

## Important limitation

The current ownership check is chain-local. Supporting communities whose NFTs
originate on another chain requires a separately reviewed origin-chain snapshot
and claim authorization design. The public application does not present that
cross-chain path as shipped.

## Public evidence versus trust

The included verifier proves current public configuration, bytecode presence,
and indexed activity. It does not prove security, regulatory compliance,
organic usage, or the absence of contract vulnerabilities. The contracts have
not received a claimed external audit.

