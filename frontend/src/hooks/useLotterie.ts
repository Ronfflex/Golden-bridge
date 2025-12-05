import {
  useAppKitAccount,
  useAppKitNetwork,
  useAppKitProvider,
} from "@reown/appkit/react";
import { BrowserProvider, Contract, Eip1193Provider } from "ethers";
import { useCallback, useMemo, useState } from "react";
import iLotterieAbi from "../../abi/lotterie/iLotterieAbi.json";
import { getContractAddress } from "../config/contracts";

export const useLotterie = () => {
  const { address, isConnected } = useAppKitAccount();
  const { chainId } = useAppKitNetwork();
  const { walletProvider } = useAppKitProvider("eip155");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const contractAddress = useMemo(
    () => getContractAddress(chainId as number, "lotterie"),
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
        return new Contract(contractAddress, iLotterieAbi.abi, signer);
      }

      return new Contract(contractAddress, iLotterieAbi.abi, ethersProvider);
    },
    [contractAddress, walletProvider]
  );

  // User-Facing Functions
  const claim = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const contract = await getContract(true);
      const tx = await contract.claim();
      await tx.wait();
    } catch (err: any) {
      setError(err.message || "Failed to claim winnings");
      throw err;
    } finally {
      setLoading(false);
    }
  }, [getContract]);

  const getGains = useCallback(
    async (account: string) => {
      try {
        const contract = await getContract(false);
        return await contract.getGains(account);
      } catch (err: any) {
        setError(err.message || "Failed to get gains");
        throw err;
      }
    },
    [getContract]
  );

  // Lottery State Functions (view)
  const getLastRequestId = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getLastRequestId();
    } catch (err: any) {
      setError(err.message || "Failed to get last request ID");
      throw err;
    }
  }, [getContract]);

  const getResults = useCallback(
    async (requestId: bigint) => {
      try {
        const contract = await getContract(false);
        return await contract.getResults(requestId);
      } catch (err: any) {
        setError(err.message || "Failed to get results");
        throw err;
      }
    },
    [getContract]
  );

  const getGoldToken = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getGoldToken();
    } catch (err: any) {
      setError(err.message || "Failed to get gold token address");
      throw err;
    }
  }, [getContract]);

  // VRF Configuration (view)
  const getVrfSubscriptionId = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getVrfSubscriptionId();
    } catch (err: any) {
      setError(err.message || "Failed to get VRF subscription ID");
      throw err;
    }
  }, [getContract]);

  const getVrfCoordinator = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getVrfCoordinator();
    } catch (err: any) {
      setError(err.message || "Failed to get VRF coordinator");
      throw err;
    }
  }, [getContract]);

  const getKeyHash = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getKeyHash();
    } catch (err: any) {
      setError(err.message || "Failed to get key hash");
      throw err;
    }
  }, [getContract]);

  const getCallbackGasLimit = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getCallbackGasLimit();
    } catch (err: any) {
      setError(err.message || "Failed to get callback gas limit");
      throw err;
    }
  }, [getContract]);

  const getRequestConfirmations = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getRequestConfirmations();
    } catch (err: any) {
      setError(err.message || "Failed to get request confirmations");
      throw err;
    }
  }, [getContract]);

  const getNumWords = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getNumWords();
    } catch (err: any) {
      setError(err.message || "Failed to get num words");
      throw err;
    }
  }, [getContract]);

  // Admin Functions (OWNER_ROLE)
  const randomDraw = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const contract = await getContract(true);
      const tx = await contract.randomDraw();
      const receipt = await tx.wait();

      // Extract requestId from transaction receipt if available
      const requestId = receipt?.logs?.[0]?.args?.[0];
      console.log("VRF Request initiated with ID:", requestId?.toString());

      return requestId;
    } catch (err: any) {
      console.error("VRF Random Draw Error:", err);

      // Provide specific error messages for common VRF issues
      let errorMessage = "Failed to initiate random draw";
      if (err.message?.includes("gas")) {
        errorMessage = "Gas estimation failed. Please try again.";
      } else if (err.message?.includes("OneRandomDrawPerDay")) {
        errorMessage =
          "Random draw can only be performed once per day. Please try again tomorrow.";
      } else if (err.message?.includes("execution reverted")) {
        errorMessage =
          "Transaction reverted. Please check your permissions and try again.";
      } else if (err.message) {
        errorMessage = err.message;
      }

      setError(errorMessage);
      throw err;
    } finally {
      setLoading(false);
    }
  }, [getContract]);

  const setGoldToken = useCallback(
    async (goldToken: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setGoldToken(goldToken);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set gold token");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const setVrfSubscriptionId = useCallback(
    async (vrfSubscriptionId: bigint) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setVrfSubscriptionId(vrfSubscriptionId);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set VRF subscription ID");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const setVrfCoordinator = useCallback(
    async (vrfCoordinator: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setVrfCoordinator(vrfCoordinator);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set VRF coordinator");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const setKeyHash = useCallback(
    async (keyHash: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setKeyHash(keyHash);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set key hash");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const setCallbackGasLimit = useCallback(
    async (callbackGasLimit: number) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setCallbackGasLimit(callbackGasLimit);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set callback gas limit");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const setRequestConfirmations = useCallback(
    async (requestConfirmations: number) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setRequestConfirmations(requestConfirmations);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set request confirmations");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const setNumWords = useCallback(
    async (numWords: number) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setNumWords(numWords);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set num words");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const addOwner = useCallback(
    async (account: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.addOwner(account);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to add owner");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const removeOwner = useCallback(
    async (account: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.removeOwner(account);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to remove owner");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const hasOwnerRole = useCallback(
    async (account: string) => {
      try {
        const contract = await getContract(false);
        return await contract.hasOwnerRole(account);
      } catch (err: any) {
        setError(err.message || "Failed to check owner role");
        throw err;
      }
    },
    [getContract]
  );

  // Diagnostic function to check VRF configuration
  const checkVrfConfiguration = useCallback(async () => {
    try {
      const [
        subscriptionId,
        coordinator,
        keyHash,
        callbackGasLimit,
        requestConfirmations,
        numWords,
      ] = await Promise.all([
        getVrfSubscriptionId(),
        getVrfCoordinator(),
        getKeyHash(),
        getCallbackGasLimit(),
        getRequestConfirmations(),
        getNumWords(),
      ]);

      console.log("VRF Configuration Check:");
      console.log("- Subscription ID:", subscriptionId.toString());
      console.log("- Coordinator:", coordinator);
      console.log("- Key Hash:", keyHash);
      console.log("- Callback Gas Limit:", callbackGasLimit.toString());
      console.log("- Request Confirmations:", requestConfirmations.toString());
      console.log("- Num Words:", numWords.toString());

      return {
        subscriptionId,
        coordinator,
        keyHash,
        callbackGasLimit,
        requestConfirmations,
        numWords,
      };
    } catch (err: any) {
      console.error("VRF Configuration Check Failed:", err);
      setError(err.message || "Failed to check VRF configuration");
      throw err;
    }
  }, [
    getVrfSubscriptionId,
    getVrfCoordinator,
    getKeyHash,
    getCallbackGasLimit,
    getRequestConfirmations,
    getNumWords,
  ]);

  // Function to manually clear error state
  const clearError = useCallback(() => {
    setError(null);
  }, []);

  return {
    loading,
    error,
    contractAddress,
    isConnected,
    address,
    clearError,
    claim,
    getGains,
    getLastRequestId,
    getResults,
    getGoldToken,
    getVrfSubscriptionId,
    getVrfCoordinator,
    getKeyHash,
    getCallbackGasLimit,
    getRequestConfirmations,
    getNumWords,
    randomDraw,
    setGoldToken,
    setVrfSubscriptionId,
    setVrfCoordinator,
    setKeyHash,
    setCallbackGasLimit,
    setRequestConfirmations,
    setNumWords,
    addOwner,
    removeOwner,
    hasOwnerRole,
    checkVrfConfiguration,
  };
};
