const getRequiredEnvVar = (key: string): string => {
  const value = import.meta.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
};

const getOptionalEnvVar = (key: string, defaultValue: string): string => {
  return import.meta.env[key] || defaultValue;
};

export const ENV = {
  REOWN_PROJECT_ID: getRequiredEnvVar("VITE_REOWN_PROJECT_ID"),
  
  CONTRACTS: {
    SEPOLIA: {
      GOLD_TOKEN: getRequiredEnvVar("VITE_CONTRACT_ADDRESS_SEPOLIA_GOLD_TOKEN"),
      LOTTERIE: getRequiredEnvVar("VITE_CONTRACT_ADDRESS_SEPOLIA_LOTTERIE"),
      TOKEN_BRIDGE: getRequiredEnvVar("VITE_CONTRACT_ADDRESS_SEPOLIA_TOKEN_BRIDGE"),
    },
    BSC_TESTNET: {
      GOLD_TOKEN: getRequiredEnvVar("VITE_CONTRACT_ADDRESS_BSC_TESTNET_GOLD_TOKEN"),
      LOTTERIE: getRequiredEnvVar("VITE_CONTRACT_ADDRESS_BSC_TESTNET_LOTTERIE"),
      TOKEN_BRIDGE: getRequiredEnvVar("VITE_CONTRACT_ADDRESS_BSC_TESTNET_TOKEN_BRIDGE"),
    },
  },

  RPC: {
    SEPOLIA: getRequiredEnvVar("VITE_RPC_URL_SEPOLIA"),
    BSC_TESTNET: getRequiredEnvVar("VITE_RPC_URL_BSC_TESTNET"),
  },

  SITE: {
    NAME: getOptionalEnvVar("VITE_SITE_NAME", "Golden Bridge"),
    DESCRIPTION: getOptionalEnvVar("VITE_SITE_DESCRIPTION", "Gold-backed tokenization with lottery rewards"),
    URL: getOptionalEnvVar("VITE_SITE_URL", "http://localhost:5173"),
    ICON: getOptionalEnvVar("VITE_SITE_ICON", "https://assets.reown.com/reown-profile-pic.png"),
  }
} as const;