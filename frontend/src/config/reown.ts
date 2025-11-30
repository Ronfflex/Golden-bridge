import { EthersAdapter } from "@reown/appkit-adapter-ethers";
import { bscTestnet, sepolia } from "@reown/appkit/networks";
import { createAppKit } from "@reown/appkit/react";
import { ENV } from "./env";

// 1. Get projectId
const projectId = ENV.REOWN_PROJECT_ID;

// 2. Set the networks
const customSepolia = {
  ...sepolia,
  rpcUrls: {
    ...sepolia.rpcUrls,
    default: {
      http: [ENV.RPC.SEPOLIA],
    },
  },
};

const customBscTestnet = {
  ...bscTestnet,
  rpcUrls: {
    ...bscTestnet.rpcUrls,
    default: {
      http: [ENV.RPC.BSC_TESTNET],
    },
  },
};

export const networks = [customSepolia, customBscTestnet];

// 3. Create a metadata object
const metadata = {
  name: ENV.SITE.NAME,
  description: ENV.SITE.DESCRIPTION,
  url: ENV.SITE.URL,
  icons: [ENV.SITE.ICON],
};

// 4. Create the AppKit instance
export const appKit = createAppKit({
  adapters: [new EthersAdapter()],
  networks: [customSepolia, customBscTestnet],
  metadata,
  projectId,
  features: {
    analytics: true,
  },
});
