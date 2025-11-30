import React, { useEffect, useRef, useState } from "react";
import { NETWORKS, SUPPORTED_CHAIN_IDS } from "../config/networks";
import { useNetwork } from "../hooks/useNetwork";
import styles from "./NetworkSwitcher.module.css";

export const NetworkSwitcher: React.FC = () => {
  const { chainId, switchNetwork, isSupportedNetwork } = useNetwork();
  const [isOpen, setIsOpen] = useState(false);
  const [isSwitching, setIsSwitching] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const currentNetwork = chainId ? NETWORKS[chainId as number] : undefined;
  const isSupported = isSupportedNetwork();

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(event.target as Node)
      ) {
        setIsOpen(false);
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const handleSwitch = async (targetChainId: number) => {
    if (targetChainId === chainId) {
      setIsOpen(false);
      return;
    }

    setIsSwitching(true);
    try {
      // Find the network object from supported networks
      // We need to pass the network object expected by AppKit, but here we are using the ID
      // The hook's switchNetwork expects a network object.
      // Let's import the network objects from AppKit networks to be safe
      const { sepolia, bscTestnet } = await import("@reown/appkit/networks");
      const targetNetwork = targetChainId === sepolia.id ? sepolia : bscTestnet;

      await switchNetwork(targetNetwork);
      setIsOpen(false);
    } catch (error) {
      console.error("Failed to switch network:", error);
    } finally {
      setIsSwitching(false);
    }
  };

  return (
    <div className={styles.container} ref={dropdownRef}>
      <button
        className={`${styles.button} ${!isSupported ? styles.unsupported : ""}`}
        onClick={() => setIsOpen(!isOpen)}
        disabled={isSwitching}
      >
        {isSwitching ? (
          <span>Switching...</span>
        ) : (
          <>
            <span
              className={styles.networkIcon}
              style={{ backgroundColor: isSupported ? "#10B981" : "#EF4444" }}
            />
            {currentNetwork?.name || "Unsupported Network"}
            <svg
              width="12"
              height="12"
              viewBox="0 0 12 12"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
              style={{
                transform: isOpen ? "rotate(180deg)" : "rotate(0)",
                transition: "transform 0.2s",
              }}
            >
              <path
                d="M2.5 4.5L6 8L9.5 4.5"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </>
        )}
      </button>

      {isOpen && (
        <div className={styles.dropdown}>
          {SUPPORTED_CHAIN_IDS.map((id) => {
            const network = NETWORKS[id];
            return (
              <button
                key={id}
                className={`${styles.menuItem} ${
                  chainId === id ? styles.active : ""
                }`}
                onClick={() => handleSwitch(id)}
              >
                <span
                  className={styles.networkIcon}
                  style={{ backgroundColor: "#10B981" }}
                />
                {network.name}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
};
