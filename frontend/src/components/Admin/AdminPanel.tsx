import React, { useCallback, useEffect, useState } from "react";
import { useAdmin } from "../../hooks/useAdmin";
import { useGoldToken } from "../../hooks/useGoldToken";
import { useLotterie } from "../../hooks/useLotterie";
import { useTokenBridge } from "../../hooks/useTokenBridge";
import { Alert } from "../ui/Alert";
import { Button } from "../ui/Button";
import { Input } from "../ui/Input";
import { InfoIcon, Tooltip } from "../ui/Tooltip";
import styles from "./AdminPanel.module.css";

interface ContractStatus {
  isPaused: boolean;
  isLoading: boolean;
}

export const AdminPanel: React.FC = () => {
  const {
    loading: adminLoading,
    isGoldTokenOwner,
    isLotterieOwner,
    isTokenBridgeOwner,
    isAnyOwner,
  } = useAdmin();

  const {
    loading: goldTokenLoading,
    pause: pauseGoldToken,
    unpause: unpauseGoldToken,
    setFeesAddress,
    setLotterieAddress,
  } = useGoldToken();

  const {
    loading: lotterieLoading,
    randomDraw,
    clearError,
    checkVrfConfiguration,
  } = useLotterie();

  const {
    loading: bridgeLoading,
    pause: pauseBridge,
    unpause: unpauseBridge,
    paused: getBridgePaused,
    setWhitelistedChain,
    setWhitelistedSender,
  } = useTokenBridge();

  const [isCollapsed, setIsCollapsed] = useState(false);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Contract statuses
  const [bridgeStatus, setBridgeStatus] = useState<ContractStatus>({
    isPaused: false,
    isLoading: true,
  });

  // Form states
  const [feesAddressInput, setFeesAddressInput] = useState("");
  const [lotterieAddressInput, setLotterieAddressInput] = useState("");
  const [whitelistChainSelector, setWhitelistChainSelector] = useState("");
  const [whitelistChainEnabled, setWhitelistChainEnabled] = useState(true);
  const [whitelistSenderAddress, setWhitelistSenderAddress] = useState("");
  const [whitelistSenderEnabled, setWhitelistSenderEnabled] = useState(true);

  // Fetch bridge status
  useEffect(() => {
    if (!isTokenBridgeOwner) return;

    let isMounted = true;

    const fetchStatus = async () => {
      try {
        const isPaused = await getBridgePaused();
        if (isMounted) {
          setBridgeStatus({ isPaused, isLoading: false });
        }
      } catch (err) {
        console.error("Failed to fetch bridge status:", err);
        if (isMounted) {
          setBridgeStatus((prev) => ({ ...prev, isLoading: false }));
        }
      }
    };

    fetchStatus();

    return () => {
      isMounted = false;
    };
  }, [isTokenBridgeOwner, getBridgePaused]);

  const refreshBridgeStatus = useCallback(async () => {
    try {
      const isPaused = await getBridgePaused();
      setBridgeStatus({ isPaused, isLoading: false });
    } catch (err) {
      console.error("Failed to fetch bridge status:", err);
    }
  }, [getBridgePaused]);

  // Handlers
  const handlePauseGoldToken = async () => {
    try {
      setErrorMsg(null);
      await pauseGoldToken();
      setSuccessMsg("GoldToken contract paused successfully!");
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to pause GoldToken");
    }
  };

  const handleUnpauseGoldToken = async () => {
    try {
      setErrorMsg(null);
      await unpauseGoldToken();
      setSuccessMsg("GoldToken contract unpaused successfully!");
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to unpause GoldToken");
    }
  };

  const handleSetFeesAddress = async () => {
    if (!feesAddressInput) return;
    try {
      setErrorMsg(null);
      await setFeesAddress(feesAddressInput);
      setSuccessMsg("Fees address updated successfully!");
      setFeesAddressInput("");
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to set fees address");
    }
  };

  const handleSetLotterieAddress = async () => {
    if (!lotterieAddressInput) return;
    try {
      setErrorMsg(null);
      await setLotterieAddress(lotterieAddressInput);
      setSuccessMsg("Lotterie address updated successfully!");
      setLotterieAddressInput("");
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to set lotterie address");
    }
  };

  const handleRandomDraw = async () => {
    try {
      setErrorMsg(null);
      const requestId = await randomDraw();
      if (requestId) {
        setSuccessMsg(
          `Random draw initiated! Request ID: ${requestId.toString()}. Waiting for VRF callback...`
        );
      } else {
        setSuccessMsg("Random draw initiated! Waiting for VRF callback...");
      }
    } catch (err: any) {
      console.error("Random draw failed:", err);
      setErrorMsg(err.message || "Failed to initiate random draw");
    }
  };

  const handleRetryRandomDraw = () => {
    setErrorMsg(null);
    setSuccessMsg(null);
    clearError();
  };

  const handleCheckVrfConfig = async () => {
    try {
      setErrorMsg(null);
      setSuccessMsg(null);
      const config = await checkVrfConfiguration();
      console.log("VRF Configuration:", config);
      setSuccessMsg("VRF configuration checked. See console for details.");
    } catch (err: any) {
      console.error("VRF config check error:", err);
      setErrorMsg(
        "Failed to check VRF configuration. See console for details."
      );
    }
  };

  const handlePauseBridge = async () => {
    try {
      setErrorMsg(null);
      await pauseBridge();
      setSuccessMsg("TokenBridge paused successfully!");
      refreshBridgeStatus();
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to pause bridge");
    }
  };

  const handleUnpauseBridge = async () => {
    try {
      setErrorMsg(null);
      await unpauseBridge();
      setSuccessMsg("TokenBridge unpaused successfully!");
      refreshBridgeStatus();
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to unpause bridge");
    }
  };

  const handleSetWhitelistedChain = async () => {
    if (!whitelistChainSelector) return;
    try {
      setErrorMsg(null);
      // Default CCIP extra args (empty for basic config)
      const ccipExtraArgs = "0x";
      await setWhitelistedChain(
        BigInt(whitelistChainSelector),
        whitelistChainEnabled,
        ccipExtraArgs
      );
      setSuccessMsg(
        `Chain ${whitelistChainSelector} ${
          whitelistChainEnabled ? "whitelisted" : "removed from whitelist"
        }!`
      );
      setWhitelistChainSelector("");
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to set whitelisted chain");
    }
  };

  const handleSetWhitelistedSender = async () => {
    if (!whitelistSenderAddress) return;
    try {
      setErrorMsg(null);
      await setWhitelistedSender(
        whitelistSenderAddress,
        whitelistSenderEnabled
      );
      setSuccessMsg(
        `Sender ${whitelistSenderAddress.substring(0, 10)}... ${
          whitelistSenderEnabled ? "whitelisted" : "removed from whitelist"
        }!`
      );
      setWhitelistSenderAddress("");
    } catch (err: any) {
      setErrorMsg(err.message || "Failed to set whitelisted sender");
    }
  };

  // Loading state
  if (adminLoading) {
    return (
      <div className={styles.adminPanel}>
        <div className={styles.loadingState}>
          <div className={styles.spinner} />
          <span>Checking admin permissions...</span>
        </div>
      </div>
    );
  }

  // Not an owner - show locked state
  if (!isAnyOwner) {
    return (
      <div className={styles.lockedPanel}>
        <div className={styles.lockedIcon}>🔒</div>
        <h3 className={styles.lockedTitle}>Admin Access Required</h3>
        <p className={styles.lockedText}>
          This section is only accessible to contract owners. Connect with an
          owner wallet to access admin functions.
        </p>
      </div>
    );
  }

  return (
    <div className={styles.adminPanel}>
      {/* Header */}
      <div className={styles.header}>
        <div className={styles.headerLeft}>
          <span className={styles.warningIcon}>⚠️</span>
          <h2 className={styles.title}>
            Admin Panel
            <InfoIcon
              tooltip="Administrative functions for contract owners. Use with caution - these actions affect all users."
              size="md"
            />
          </h2>
          <span className={styles.badge}>
            <span>🔑</span> Owner Access
          </span>
        </div>
        <button
          className={styles.collapseButton}
          onClick={() => setIsCollapsed(!isCollapsed)}
        >
          {isCollapsed ? "▼ Expand" : "▲ Collapse"}
        </button>
      </div>

      {/* Alerts */}
      {successMsg && (
        <Alert
          type="success"
          className="mb-4"
          onClose={() => setSuccessMsg(null)}
        >
          {successMsg}
        </Alert>
      )}
      {errorMsg && (
        <Alert type="error" className="mb-4" onClose={() => setErrorMsg(null)}>
          {errorMsg}
        </Alert>
      )}

      {/* Content */}
      <div
        className={`${styles.content} ${
          isCollapsed ? styles.contentCollapsed : ""
        }`}
      >
        {/* Warning Box */}
        <div className={styles.warningBox}>
          <span className={styles.warningBoxIcon}>⚠️</span>
          <div className={styles.warningBoxContent}>
            <div className={styles.warningBoxTitle}>Caution Required</div>
            <div className={styles.warningBoxText}>
              Admin actions are irreversible and affect all users. Pausing
              contracts will prevent all user interactions. Ensure you
              understand the implications before proceeding.
            </div>
          </div>
        </div>

        {/* GoldToken Admin Section */}
        {isGoldTokenOwner && (
          <div className={styles.contractSection}>
            <div className={styles.contractHeader}>
              <h3 className={styles.contractTitle}>
                <span className={styles.contractIcon}>🪙</span>
                GoldToken Administration
              </h3>
              <Tooltip content="You have owner access to GoldToken contract">
                <span
                  className={`${styles.statusBadge} ${styles.statusActive}`}
                >
                  ✓ Owner
                </span>
              </Tooltip>
            </div>

            <div className={styles.adminActions}>
              <Tooltip content="Pause all minting and burning operations">
                <button
                  className={`${styles.adminButton} ${styles.adminButtonDanger}`}
                  onClick={handlePauseGoldToken}
                  disabled={goldTokenLoading}
                >
                  ⏸️ Pause Contract
                </button>
              </Tooltip>
              <Tooltip content="Resume normal contract operations">
                <button
                  className={`${styles.adminButton} ${styles.adminButtonSuccess}`}
                  onClick={handleUnpauseGoldToken}
                  disabled={goldTokenLoading}
                >
                  ▶️ Unpause Contract
                </button>
              </Tooltip>
            </div>

            {/* Set Fees Address */}
            <div className={styles.formSection}>
              <div className={styles.formTitle}>Update Fees Address</div>
              <div className={styles.formRow}>
                <div className={styles.formInput}>
                  <Input
                    placeholder="0x... (new fees address)"
                    value={feesAddressInput}
                    onChange={(e) => setFeesAddressInput(e.target.value)}
                  />
                </div>
                <Button
                  variant="secondary"
                  onClick={handleSetFeesAddress}
                  disabled={goldTokenLoading || !feesAddressInput}
                  isLoading={goldTokenLoading}
                >
                  Update
                </Button>
              </div>
            </div>

            {/* Set Lotterie Address */}
            <div className={styles.formSection}>
              <div className={styles.formTitle}>Update Lotterie Address</div>
              <div className={styles.formRow}>
                <div className={styles.formInput}>
                  <Input
                    placeholder="0x... (new lotterie address)"
                    value={lotterieAddressInput}
                    onChange={(e) => setLotterieAddressInput(e.target.value)}
                  />
                </div>
                <Button
                  variant="secondary"
                  onClick={handleSetLotterieAddress}
                  disabled={goldTokenLoading || !lotterieAddressInput}
                  isLoading={goldTokenLoading}
                >
                  Update
                </Button>
              </div>
            </div>
          </div>
        )}

        {/* Lotterie Admin Section */}
        {isLotterieOwner && (
          <div className={styles.contractSection}>
            <div className={styles.contractHeader}>
              <h3 className={styles.contractTitle}>
                <span className={styles.contractIcon}>🎰</span>
                Lotterie Administration
              </h3>
              <Tooltip content="You have owner access to Lotterie contract">
                <span
                  className={`${styles.statusBadge} ${styles.statusActive}`}
                >
                  ✓ Owner
                </span>
              </Tooltip>
            </div>

            <div className={styles.adminActions}>
              <div className={styles.adminActions}>
                <Tooltip content="Initiate a new lottery draw using Chainlink VRF. Can only be done once per day.">
                  <button
                    className={`${styles.adminButton} ${styles.adminButtonPrimary}`}
                    onClick={handleRandomDraw}
                    disabled={lotterieLoading || !!errorMsg}
                  >
                    {lotterieLoading
                      ? "⏳ Processing..."
                      : "🎲 Trigger Random Draw"}
                  </button>
                </Tooltip>

                {/* Retry Button - shown when there's an error */}
                {errorMsg && (
                  <Tooltip content="Clear the error state and try again">
                    <button
                      className={`${styles.adminButton} ${styles.adminButtonSecondary}`}
                      onClick={handleRetryRandomDraw}
                      disabled={lotterieLoading}
                    >
                      🔄 Retry
                    </button>
                  </Tooltip>
                )}

                {/* Debug Button - always visible for troubleshooting */}
                <Tooltip content="Check VRF configuration and settings">
                  <button
                    className={`${styles.adminButton} ${styles.adminButtonSecondary}`}
                    onClick={handleCheckVrfConfig}
                    disabled={lotterieLoading}
                  >
                    🔧 Debug VRF
                  </button>
                </Tooltip>
              </div>
            </div>
          </div>
        )}

        {/* TokenBridge Admin Section */}
        {isTokenBridgeOwner && (
          <div className={styles.contractSection}>
            <div className={styles.contractHeader}>
              <h3 className={styles.contractTitle}>
                <span className={styles.contractIcon}>🌉</span>
                TokenBridge Administration
              </h3>
              <div style={{ display: "flex", gap: "0.5rem" }}>
                <Tooltip content="You have owner access to TokenBridge contract">
                  <span
                    className={`${styles.statusBadge} ${styles.statusActive}`}
                  >
                    ✓ Owner
                  </span>
                </Tooltip>
                {bridgeStatus.isLoading ? (
                  <span
                    className={`${styles.statusBadge} ${styles.statusUnknown}`}
                  >
                    Loading...
                  </span>
                ) : (
                  <span
                    className={`${styles.statusBadge} ${
                      bridgeStatus.isPaused
                        ? styles.statusPaused
                        : styles.statusActive
                    }`}
                  >
                    {bridgeStatus.isPaused ? "⏸️ Paused" : "✅ Active"}
                  </span>
                )}
              </div>
            </div>

            <div className={styles.adminActions}>
              <Tooltip content="Pause all bridge operations">
                <button
                  className={`${styles.adminButton} ${styles.adminButtonDanger}`}
                  onClick={handlePauseBridge}
                  disabled={bridgeLoading || bridgeStatus.isPaused}
                >
                  ⏸️ Pause Bridge
                </button>
              </Tooltip>
              <Tooltip content="Resume bridge operations">
                <button
                  className={`${styles.adminButton} ${styles.adminButtonSuccess}`}
                  onClick={handleUnpauseBridge}
                  disabled={bridgeLoading || !bridgeStatus.isPaused}
                >
                  ▶️ Unpause Bridge
                </button>
              </Tooltip>
            </div>

            {/* Whitelist Chain */}
            <div className={styles.formSection}>
              <div className={styles.formTitle}>
                Whitelist Chain
                <InfoIcon
                  tooltip="Add or remove chains from the whitelist. Use chain selectors: Sepolia=16015286601757825753, BSC=13264668187771770619"
                  size="sm"
                />
              </div>
              <div className={styles.formRow}>
                <div className={styles.formInput}>
                  <Input
                    placeholder="Chain selector (e.g., 16015286601757825753)"
                    value={whitelistChainSelector}
                    onChange={(e) => setWhitelistChainSelector(e.target.value)}
                  />
                </div>
                <label
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "0.5rem",
                  }}
                >
                  <input
                    type="checkbox"
                    checked={whitelistChainEnabled}
                    onChange={(e) => setWhitelistChainEnabled(e.target.checked)}
                  />
                  Enable
                </label>
                <Button
                  variant="secondary"
                  onClick={handleSetWhitelistedChain}
                  disabled={bridgeLoading || !whitelistChainSelector}
                  isLoading={bridgeLoading}
                >
                  Update
                </Button>
              </div>
            </div>

            {/* Whitelist Sender */}
            <div className={styles.formSection}>
              <div className={styles.formTitle}>
                Whitelist Sender
                <InfoIcon
                  tooltip="Add or remove sender addresses from the whitelist for cross-chain messages"
                  size="sm"
                />
              </div>
              <div className={styles.formRow}>
                <div className={styles.formInput}>
                  <Input
                    placeholder="0x... (sender address)"
                    value={whitelistSenderAddress}
                    onChange={(e) => setWhitelistSenderAddress(e.target.value)}
                  />
                </div>
                <label
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "0.5rem",
                  }}
                >
                  <input
                    type="checkbox"
                    checked={whitelistSenderEnabled}
                    onChange={(e) =>
                      setWhitelistSenderEnabled(e.target.checked)
                    }
                  />
                  Enable
                </label>
                <Button
                  variant="secondary"
                  onClick={handleSetWhitelistedSender}
                  disabled={bridgeLoading || !whitelistSenderAddress}
                  isLoading={bridgeLoading}
                >
                  Update
                </Button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
