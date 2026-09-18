import deployment from '../deployment.json' with { type: 'json' };

const ZERO_CODE = '0x';

async function json(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  return response.json();
}

async function rpc(method, params = []) {
  const payload = await json(deployment.rpcUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params })
  });
  if (payload.error) throw new Error(`${method}: ${payload.error.message}`);
  return payload.result;
}

function sameAddress(left, right) {
  return String(left).toLowerCase() === String(right).toLowerCase();
}

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

const [chainHex, siteConfig, analytics] = await Promise.all([
  rpc('eth_chainId'),
  json(`${deployment.liveApplication}/api/config`),
  json(`${deployment.liveApplication}/api/v4/analytics`)
]);

requireValue(Number.parseInt(chainHex, 16) === deployment.chainId, 'Arc chain ID mismatch');
requireValue(siteConfig.chainId === deployment.chainId, 'Public application is not on Arc mainnet');
requireValue(siteConfig.status === 'ready' && siteConfig.storage === 'published', 'Public runtime is not ready');
requireValue(siteConfig.v5?.status === 'ready', 'V5 runtime is not ready');
requireValue(sameAddress(siteConfig.v5.factory, deployment.v5.factory), 'V5 factory mismatch');
requireValue(sameAddress(siteConfig.v5.poolHook, deployment.v5.feeHook), 'V5 hook mismatch');
requireValue(sameAddress(siteConfig.v5.router, deployment.v5.router), 'V5 router mismatch');
requireValue(sameAddress(siteConfig.v5.poolManager, deployment.uniswapV4PoolManager), 'PoolManager mismatch');
requireValue(analytics.stale === false, 'Public analytics are stale');

const contracts = [
  deployment.usdc,
  deployment.uniswapV4PoolManager,
  deployment.v5.factory,
  deployment.v5.feeHook,
  deployment.v5.router,
  deployment.v4PublicApplication.factory,
  deployment.v4PublicApplication.platformToken
];

const codes = await Promise.all(contracts.map((address) => rpc('eth_getCode', [address, 'latest'])));
codes.forEach((code, index) => requireValue(code !== ZERO_CODE, `No bytecode at ${contracts[index]}`));

const launchCountHex = await rpc('eth_call', [
  { to: deployment.v5.factory, data: '0x27cca59f' },
  'latest'
]);

const result = {
  verifiedAt: new Date().toISOString(),
  chainId: deployment.chainId,
  publicRuntime: siteConfig.status,
  v5LaunchCount: Number(BigInt(launchCountHex)),
  indexedBlock: analytics.indexedBlock,
  analytics: {
    launches: analytics.overview.coinsLaunched,
    trades: analytics.overview.totalTrades,
    uniqueTraders: analytics.overview.uniqueTraders,
    volumeUsdc: (Number(analytics.overview.totalVolumeUsdcRaw) / 1e6).toFixed(6),
    recordedFeesUsdc: (Number(analytics.overview.totalFeesUsdcRaw) / 1e6).toFixed(6),
    feeShareNftsMinted: analytics.overview.nftsMinted
  },
  checkedContracts: contracts
};

console.log(JSON.stringify(result, null, 2));

