import {
  useAppKitAccount,
  useAppKitNetwork,
  useAppKitProvider,
} from "@reown/appkit/react";
import { BrowserProvider, Contract, Eip1193Provider } from "ethers";
import { useCallback, useMemo, useState } from "react";
import iGoldTokenAbi from "../../abi/goldToken/iGoldTokenAbi.json";
import { getContractAddress } from "../config/contracts";

export const useGoldToken = () => {
  const { address, isConnected } = useAppKitAccount();
  const { chainId } = useAppKitNetwork();
  const { walletProvider } = useAppKitProvider("eip155");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const contractAddress = useMemo(
    () => getContractAddress(chainId as number, "goldToken"),
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
        return new Contract(contractAddress, iGoldTokenAbi.abi, signer);
      }

      return new Contract(contractAddress, iGoldTokenAbi.abi, ethersProvider);
    },
    [contractAddress, walletProvider]
  );

  // User-Facing Functions
  const mint = useCallback(
    async (value: bigint) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.mint({ value });
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to mint tokens");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const burn = useCallback(
    async (amount: bigint) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.burn(amount);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to burn tokens");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const transfer = useCallback(
    async (to: string, amount: bigint) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.transfer(to, amount);
        await tx.wait();
        return true;
      } catch (err: any) {
        setError(err.message || "Failed to transfer tokens");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const balanceOf = useCallback(
    async (account: string) => {
      try {
        const contract = await getContract(false);
        return await contract.balanceOf(account);
      } catch (err: any) {
        setError(err.message || "Failed to get balance");
        throw err;
      }
    },
    [getContract]
  );

  const claimEth = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const contract = await getContract(true);
      const tx = await contract.claimEth();
      await tx.wait();
    } catch (err: any) {
      setError(err.message || "Failed to claim ETH");
      throw err;
    } finally {
      setLoading(false);
    }
  }, [getContract]);

  // View Functions
  const getGoldPriceInEth = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getGoldPriceInEth();
    } catch (err: any) {
      setError(err.message || "Failed to get gold price");
      throw err;
    }
  }, [getContract]);

  const getFees = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getFees();
    } catch (err: any) {
      setError(err.message || "Failed to get fees");
      throw err;
    }
  }, [getContract]);

  const getFeesAddress = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getFeesAddress();
    } catch (err: any) {
      setError(err.message || "Failed to get fees address");
      throw err;
    }
  }, [getContract]);

  const getUsers = useCallback(async () => {
    try {
      const contract = await getContract(false);
      return await contract.getUsers();
    } catch (err: any) {
      setError(err.message || "Failed to get users");
      throw err;
    }
  }, [getContract]);

  const getTimestamps = useCallback(async () => {
    try {
      const contract = await getContract(false);
      const [users, timestamps] = await contract.getTimestamps();
      return { users, timestamps };
    } catch (err: any) {
      setError(err.message || "Failed to get timestamps");
      throw err;
    }
  }, [getContract]);

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

  // Admin Functions
  const setFeesAddress = useCallback(
    async (feesAddress: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setFeesAddress(feesAddress);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set fees address");
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [getContract]
  );

  const setLotterieAddress = useCallback(
    async (lotterieAddress: string) => {
      setLoading(true);
      setError(null);
      try {
        const contract = await getContract(true);
        const tx = await contract.setLotterieAddress(lotterieAddress);
        await tx.wait();
      } catch (err: any) {
        setError(err.message || "Failed to set lottery address");
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

  const pause = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const contract = await getContract(true);
      const tx = await contract.pause();
      await tx.wait();
    } catch (err: any) {
      setError(err.message || "Failed to pause contract");
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
      setError(err.message || "Failed to unpause contract");
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
    mint,
    burn,
    transfer,
    balanceOf,
    claimEth,
    getGoldPriceInEth,
    getFees,
    getFeesAddress,
    getUsers,
    getTimestamps,
    hasOwnerRole,
    setFeesAddress,
    setLotterieAddress,
    addOwner,
    removeOwner,
    pause,
    unpause,
  };
};
