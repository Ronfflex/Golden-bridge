import {
  useAppKitAccount,
  useAppKitNetwork,
  useAppKitProvider,
} from "@reown/appkit/react";
import { BrowserProvider, Contract, Eip1193Provider } from "ethers";
import { useCallback, useEffect, useMemo, useState } from "react";
import iGoldTokenAbi from "../../abi/goldToken/iGoldTokenAbi.json";
import iLotterieAbi from "../../abi/lotterie/iLotterieAbi.json";
import tokenBridgeAbi from "../../abi/tokenBridge/tokenBridgeAbi.json";
import { getContractAddress } from "../config/contracts";

export interface AdminStatus {
  isGoldTokenOwner: boolean;
  isLotterieOwner: boolean;
  isTokenBridgeOwner: boolean;
  isAnyOwner: boolean;
  isAllOwner: boolean;
}

export const useAdmin = () => {
  const { address, isConnected } = useAppKitAccount();
  const { chainId } = useAppKitNetwork();
  const { walletProvider } = useAppKitProvider("eip155");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [adminStatus, setAdminStatus] = useState<AdminStatus>({
    isGoldTokenOwner: false,
    isLotterieOwner: false,
    isTokenBridgeOwner: false,
    isAnyOwner: false,
    isAllOwner: false,
  });

  const goldTokenAddress = useMemo(
    () => getContractAddress(chainId as number, "goldToken"),
    [chainId]
  );

  const lotterieAddress = useMemo(
    () => getContractAddress(chainId as number, "lotterie"),
    [chainId]
  );

  const tokenBridgeAddress = useMemo(
    () => getContractAddress(chainId as number, "tokenBridge"),
    [chainId]
  );

  const getProvider = useCallback(async () => {
    if (!walletProvider) throw new Error("Wallet not connected");
    return new BrowserProvider(walletProvider as Eip1193Provider);
  }, [walletProvider]);

  const checkOwnerRole = useCallback(async () => {
    if (!address || !isConnected) {
      setAdminStatus({
        isGoldTokenOwner: false,
        isLotterieOwner: false,
        isTokenBridgeOwner: false,
        isAnyOwner: false,
        isAllOwner: false,
      });
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const provider = await getProvider();
      const results = {
        isGoldTokenOwner: false,
        isLotterieOwner: false,
        isTokenBridgeOwner: false,
      };

      // Check GoldToken owner role
      if (goldTokenAddress) {
        try {
          const goldTokenContract = new Contract(
            goldTokenAddress,
            iGoldTokenAbi.abi,
            provider
          );
          results.isGoldTokenOwner = await goldTokenContract.hasOwnerRole(
            address
          );
        } catch (err) {
          console.warn("Failed to check GoldToken owner role:", err);
        }
      }

      // Check Lotterie owner role
      if (lotterieAddress) {
        try {
          const lotterieContract = new Contract(
            lotterieAddress,
            iLotterieAbi.abi,
            provider
          );
          results.isLotterieOwner = await lotterieContract.hasOwnerRole(
            address
          );
        } catch (err) {
          console.warn("Failed to check Lotterie owner role:", err);
        }
      }

      // Check TokenBridge owner role
      if (tokenBridgeAddress) {
        try {
          const tokenBridgeContract = new Contract(
            tokenBridgeAddress,
            tokenBridgeAbi.abi,
            provider
          );
          // TokenBridge uses hasRole with OWNER_ROLE constant
          const OWNER_ROLE =
            "0xb19546dff01e856fb3f010c267a7b1c60363cf8a4664e21cc89c26224620214e";
          results.isTokenBridgeOwner = await tokenBridgeContract.hasRole(
            OWNER_ROLE,
            address
          );
        } catch (err) {
          console.warn("Failed to check TokenBridge owner role:", err);
        }
      }

      const isAnyOwner =
        results.isGoldTokenOwner ||
        results.isLotterieOwner ||
        results.isTokenBridgeOwner;

      const isAllOwner =
        results.isGoldTokenOwner &&
        results.isLotterieOwner &&
        results.isTokenBridgeOwner;

      setAdminStatus({
        ...results,
        isAnyOwner,
        isAllOwner,
      });
    } catch (err: any) {
      setError(err.message || "Failed to check admin status");
      console.error("Error checking admin status:", err);
    } finally {
      setLoading(false);
    }
  }, [
    address,
    isConnected,
    getProvider,
    goldTokenAddress,
    lotterieAddress,
    tokenBridgeAddress,
  ]);

  // Check owner role when wallet connects or chain changes
  useEffect(() => {
    if (isConnected && address) {
      checkOwnerRole();
    }
  }, [isConnected, address, chainId, checkOwnerRole]);

  return {
    loading,
    error,
    ...adminStatus,
    checkOwnerRole,
    address,
    isConnected,
  };
};
