import { bscTestnet, sepolia } from "@reown/appkit/networks";
import { ENV } from "./env";

export const CONTRACT_ADDRESSES = {
  [sepolia.id]: {
    goldToken: ENV.CONTRACTS.SEPOLIA.GOLD_TOKEN,
    lotterie: ENV.CONTRACTS.SEPOLIA.LOTTERIE,
    tokenBridge: ENV.CONTRACTS.SEPOLIA.TOKEN_BRIDGE,
  },
  [bscTestnet.id]: {
    goldToken: ENV.CONTRACTS.BSC_TESTNET.GOLD_TOKEN,
    lotterie: ENV.CONTRACTS.BSC_TESTNET.LOTTERIE,
    tokenBridge: ENV.CONTRACTS.BSC_TESTNET.TOKEN_BRIDGE,
  },
} as const;

export type ChainId = keyof typeof CONTRACT_ADDRESSES;

export const getContractAddress = (
  chainId: number | undefined,
  contract: "goldToken" | "lotterie" | "tokenBridge"
): string | undefined => {
  if (!chainId) return undefined;
  return CONTRACT_ADDRESSES[chainId as ChainId]?.[contract];
};
