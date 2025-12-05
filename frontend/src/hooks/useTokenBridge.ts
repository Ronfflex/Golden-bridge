import {
  useAppKitAccount,
  useAppKitNetwork,
  useAppKitProvider,
} from "@reown/appkit/react";
import { BrowserProvider, Contract, Eip1193Provider } from "ethers";
import { useCallback, useMemo, useState } from "react";
import tokenBridgeAbi from "../../abi/tokenBridge/tokenBridgeAbi.json";
import { getContractAddress } from "../config/contracts";
import { PayFeesIn } from "../types/tokenBridge";

export const useTokenBridge = () => {
  const { address, isConnected } = useAppKitAccount();
  const { chainId } = useAppKitNetwork();
  const { walletProvider } = useAppKitProvider("eip155");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const contractAddress = useMemo(
    () => getContractAddress(chainId as number, "tokenBridge"),
    [chainId]
  );

  const getContract = useCallback(
    async (withSigner = false) => {
      if (!contractAddress)
        throw new Error("Contract not deployed on this network");
      if (!walletProvider) throw new Error("Wallet not connected");

      const ethersProvider = new BrowserProvider(
        walletProvider as Eip1193Provider
      );

      if (withSigner) {
        const signer = await ethersProvider.getSigner();
        return new Contract(contractAddress, tokenBridgeAbi.abi, signer);
      }

      return new Contract(contractAddress, tokenBridgeAbi.abi, ethersProvider);
    },
    [contractAddress, walletProvider]
  );

  // User-Facing Functions
  const bridgeTokens = useCallback(
    async (receiver: string, amount: bigint, payFeesIn: PayFeesIn) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.bridgeTokens(receiver, amount, payFeesIn);
        const receipt = await tx.wait();
        // Find the TokensBridged event to get the messageId
        // This is a simplification, in a real app we might want to parse logs
        return receipt;
      } catch (err: any) {
        setError(err.message || "Failed to bridge tokens");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  // State Query Functions (view)
  const getDestinationChainSelector = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.destinationChainSelector();
    } catch (err: any) {
      setError(err.message || "Failed to get destination chain selector");
      throw err;
    }
  }, [getContract]);

  const getGoldToken = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.goldToken();
    } catch (err: any) {
      setError(err.message || "Failed to get gold token address");
      throw err;
    }
  }, [getContract]);

  const getLink = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.link();
    } catch (err: any) {
      setError(err.message || "Failed to get LINK token address");
      throw err;
    }
  }, [getContract]);

  const getGoldTokenBalance = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getGoldTokenBalance();
    } catch (err: any) {
      setError(err.message || "Failed to get gold token balance");
      throw err;
    }
  }, [getContract]);

  const getLinkBalance = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getLinkBalance();
    } catch (err: any) {
      setError(err.message || "Failed to get LINK balance");
      throw err;
    }
  }, [getContract]);

  const getProcessedMessages = useCallback(
    async (messageId: string) => {
      try {
        const contract = await getContract(false);
        return await contract.processedMessages(messageId);
      } catch (err: any) {
        setError(err.message || "Failed to check processed message");
        throw err;
      }
    },
    [getContract]
  );

  const getWhitelistedChains = useCallback(
    async (chainSelector: bigint) => {
      try {
        const contract = await getContract(false);
        return await contract.whitelistedChains(chainSelector);
      } catch (err: any) {
        setError(err.message || "Failed to check whitelisted chain");
        throw err;
      }
    },
    [getContract]
  );

  const getWhitelistedSenders = useCallback(
    async (sender: string) => {
      try {
        const contract = await getContract(false);
        return await contract.whitelistedSenders(sender);
      } catch (err: any) {
        setError(err.message || "Failed to check whitelisted sender");
        throw err;
      }
    },
    [getContract]
  );

  const paused = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.paused();
    } catch (err: any) {
      setError(err.message || "Failed to check pause status");
      throw err;
    }
  }, [getContract]);

  // Admin Functions (OWNER_ROLE)
  const setWhitelistedChain = useCallback(
    async (chainSelector: bigint, enabled: boolean, ccipExtraArgs: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setWhitelistedChain(
          chainSelector,
          enabled,
          ccipExtraArgs
        );
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set whitelisted chain");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const setWhitelistedSender = useCallback(
    async (sender: string, enabled: boolean) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setWhitelistedSender(sender, enabled);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set whitelisted sender");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const withdraw = useCallback(
    async (beneficiary: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.withdraw(beneficiary);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to withdraw ETH");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const withdrawToken = useCallback(
    async (beneficiary: string, token: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.withdrawToken(beneficiary, token);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to withdraw token");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const pause = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const contract = await getContract(true);
      const tx = await contract.pause();
      await tx.wait();
    } catch (err: any) {
      setError(err.message || "Failed to pause bridge");
      throw err;
    } finally {
      setLoading(false);
    }
  }, [getContract]);

  const unpause = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const contract = await getContract(true);
      const tx = await contract.unpause();
      await tx.wait();
    } catch (err: any) {
      setError(err.message || "Failed to unpause bridge");
      throw err;
    } finally {
      setLoading(false);
    }
  }, [getContract]);

  return {
    loading,
    error,
    contractAddress,
    isConnected,
    address,
    bridgeTokens,
    getDestinationChainSelector,
    getGoldToken,
    getLink,
    getGoldTokenBalance,
    getLinkBalance,
    getProcessedMessages,
    getWhitelistedChains,
    getWhitelistedSenders,
    paused,
    setWhitelistedChain,
    setWhitelistedSender,
    withdraw,
    withdrawToken,
    pause,
    unpause,
  };
};
