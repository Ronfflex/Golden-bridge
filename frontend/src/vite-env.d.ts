/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_REOWN_PROJECT_ID: string;
  readonly VITE_CONTRACT_ADDRESS_SEPOLIA_GOLD_TOKEN: string;
  readonly VITE_CONTRACT_ADDRESS_SEPOLIA_LOTTERIE: string;
  readonly VITE_CONTRACT_ADDRESS_SEPOLIA_TOKEN_BRIDGE: string;
  readonly VITE_CONTRACT_ADDRESS_BSC_TESTNET_GOLD_TOKEN: string;
  readonly VITE_CONTRACT_ADDRESS_BSC_TESTNET_LOTTERIE: string;
  readonly VITE_CONTRACT_ADDRESS_BSC_TESTNET_TOKEN_BRIDGE: string;
  readonly VITE_RPC_URL_SEPOLIA: string;
  readonly VITE_RPC_URL_BSC_TESTNET: string;
  readonly VITE_SITE_NAME: string;
  readonly VITE_SITE_DESCRIPTION: string;
  readonly VITE_SITE_URL: string;
  readonly VITE_SITE_ICON: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
