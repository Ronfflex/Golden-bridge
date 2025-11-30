import { bscTestnet, sepolia } from "@reown/appkit/networks";
import { useAppKitNetwork } from "@reown/appkit/react";
import { isSupportedNetwork as checkSupported } from "../config/networks";

export const useNetwork = () => {
  const { chainId, switchNetwork } = useAppKitNetwork();

  const isSepoliaNetwork = () => chainId === sepolia.id;
  const isBscTestnet = () => chainId === bscTestnet.id;
  const isSupportedNetwork = () => checkSupported(chainId as number);

  const switchToSepolia = async () => {
    try {
      await switchNetwork(sepolia);
    } catch (error) {
      console.error("Failed to switch to Sepolia:", error);
      throw error;
    }
  };

  const switchToBscTestnet = async () => {
    try {
      await switchNetwork(bscTestnet);
    } catch (error) {
      console.error("Failed to switch to BSC Testnet:", error);
      throw error;
    }
  };

  return {
    chainId,
    isSepoliaNetwork,
    isBscTestnet,
    isSupportedNetwork,
    switchToSepolia,
    switchToBscTestnet,
    switchNetwork,
  };
};
