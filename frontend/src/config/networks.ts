import { bscTestnet, sepolia } from "@reown/appkit/networks";
import { ENV } from "./env";

export interface NetworkConfig {
  chainId: number;
  name: string;
  currency: string;
  explorerUrl: string;
  rpcUrl: string;
  icon?: string;
}

export const NETWORKS: Record<number, NetworkConfig> = {
  [sepolia.id]: {
    chainId: sepolia.id,
    name: "Sepolia Testnet",
    currency: "ETH",
    explorerUrl: "https://sepolia.etherscan.io",
    rpcUrl: ENV.RPC.SEPOLIA,
  },
  [bscTestnet.id]: {
    chainId: bscTestnet.id,
    name: "BSC Testnet",
    currency: "tBNB",
    explorerUrl: "https://testnet.bscscan.com",
    rpcUrl: ENV.RPC.BSC_TESTNET,
  },
};

export const SUPPORTED_CHAIN_IDS = [sepolia.id, bscTestnet.id];

export const getNetworkConfig = (
  chainId: number | undefined
): NetworkConfig | undefined => {
  if (!chainId) return undefined;
  return NETWORKS[chainId];
};

export const isSupportedNetwork = (chainId: number | undefined): boolean => {
  if (!chainId) return false;
  return SUPPORTED_CHAIN_IDS.includes(chainId as any);
};

export const getExplorerLink = (
  chainId: number | undefined,
  hash: string,
  type: "tx" | "address" = "tx"
): string => {
  const config = getNetworkConfig(chainId);
  if (!config) return "#";
  return `${config.explorerUrl}/${type}/${hash}`;
};
