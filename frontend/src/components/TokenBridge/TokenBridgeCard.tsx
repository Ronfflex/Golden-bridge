import { formatEther, parseEther } from "ethers";
import React, { useEffect, useState } from "react";
import { NETWORKS } from "../../config/networks";
import { useNetwork } from "../../hooks/useNetwork";
import { useTokenBridge } from "../../hooks/useTokenBridge";
import { PayFeesIn } from "../../types/tokenBridge";
import { Alert } from "../ui/Alert";
import { Badge } from "../ui/Badge";
import { Button } from "../ui/Button";
import { Card } from "../ui/Card";
import { FeatureItem, HighlightBox, InfoCard } from "../ui/InfoCard";
import { Input } from "../ui/Input";
import { InfoIcon, Tooltip } from "../ui/Tooltip";
import styles from "./TokenBridgeCard.module.css";

export const TokenBridgeCard: React.FC = () => {
  const {
    loading,
    error,
    isConnected,
    address,
    bridgeTokens,
    getDestinationChainSelector,
    getGoldTokenBalance,
    paused,
  } = useTokenBridge();

  const { chainId } = useNetwork();

  const [bridgeBalance, setBridgeBalance] = useState<string>("0");
  const [destChainSelector, setDestChainSelector] = useState<string>("0");
  const [isPaused, setIsPaused] = useState(false);
  const [receiver, setReceiver] = useState("");
  const [amount, setAmount] = useState("");
  const [payFeesIn, setPayFeesIn] = useState<PayFeesIn>(PayFeesIn.Native);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [showEducation, setShowEducation] = useState(true);

  const fetchData = async () => {
    try {
      const [bal, selector, pausedState] = await Promise.allSettled([
        getGoldTokenBalance(),
        getDestinationChainSelector(),
        paused(),
      ]);

      if (bal.status === "fulfilled") {
        setBridgeBalance(formatEther(bal.value));
      }

      if (selector.status === "fulfilled") {
        setDestChainSelector(selector.value.toString());
      }

      if (pausedState.status === "fulfilled") {
        setIsPaused(pausedState.value);
      }

      const rejected = [bal, selector, pausedState].filter(
        (r) => r.status === "rejected"
      );
      if (rejected.length > 0) {
        console.warn(
          "Some bridge data fetches failed:",
          rejected.map((r) => (r as PromiseRejectedResult).reason)
        );
      }
    } catch (err) {
      console.error("Error fetching bridge data:", err);
    }
  };

  useEffect(() => {
    if (isConnected && address) {
      setReceiver(address);
      fetchData();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConnected, address]);

  const handleBridge = async () => {
    try {
      setSuccessMsg(null);
      if (!receiver || !amount) return;

      await bridgeTokens(receiver, parseEther(amount), payFeesIn);

      setSuccessMsg(`Successfully initiated bridge transfer of ${amount} GLD!`);
      setAmount("");
      fetchData();
    } catch (err) {
      console.error(err);
    }
  };

  const getDestNetworkName = (selector: string) => {
    if (selector === "16015286601757825753") return "Sepolia Testnet";
    if (selector === "13264668187771770619") return "BSC Testnet";
    return "Unknown Chain";
  };

  const getDestNetworkIcon = (selector: string) => {
    if (selector === "16015286601757825753") return "🔷"; // Ethereum
    if (selector === "13264668187771770619") return "🟡"; // BSC
    return "❓";
  };

  const currentNetwork = chainId ? NETWORKS[chainId as number] : undefined;
  const currentNetworkIcon =
    chainId === 11155111 ? "🔷" : chainId === 97 ? "🟡" : "❓";

  return (
    <Card className={styles.card}>
      <Card.Header
        title={
          <span className={styles.headerTitle}>
            🌉 Cross-Chain Bridge
            <InfoIcon
              tooltip={
                <span>
                  <strong>Chainlink CCIP Bridge</strong>
                  <br />
                  Transfer GLD tokens securely between Ethereum and BSC using
                  Chainlink's Cross-Chain Interoperability Protocol.
                </span>
              }
              size="md"
            />
          </span>
        }
        subtitle="Transfer GLD between networks"
        action={
          <Tooltip
            content={
              isPaused
                ? "Bridge is currently paused for maintenance"
                : "Bridge is operational and ready for transfers"
            }
          >
            <Badge variant={isPaused ? "error" : "success"}>
              {isPaused ? "⏸️ Paused" : "✅ Active"}
            </Badge>
          </Tooltip>
        }
      />
      <Card.Body>
        {/* Educational Section */}
        {showEducation && (
          <InfoCard
            title="What is Cross-Chain Bridging?"
            icon="🌐"
            variant="highlight"
            collapsible
            defaultExpanded={true}
          >
            <p>
              Cross-chain bridging allows you to transfer your GLD tokens
              between different blockchain networks. This enables you to use
              your tokens on whichever network offers the best opportunities.
            </p>
            <HighlightBox variant="info">
              <strong>🔗 Powered by Chainlink CCIP</strong>
              <br />
              CCIP (Cross-Chain Interoperability Protocol) is Chainlink's secure
              messaging protocol that enables safe token transfers across
              blockchains.
            </HighlightBox>
            <FeatureItem
              icon="🔒"
              title="Secure Transfers"
              description="CCIP uses multiple layers of security including decentralized oracle networks and risk management systems."
            />
            <FeatureItem
              icon="⏱️"
              title="Transfer Time"
              description="Transfers typically complete in 15-30 minutes, depending on network conditions and confirmations required."
            />
            <FeatureItem
              icon="💰"
              title="Bridge Fees"
              description="Pay fees in either native tokens (ETH/BNB) or LINK. LINK payments often offer better rates."
            />
          </InfoCard>
        )}

        {/* Network Flow Visualization */}
        <div className={styles.networkFlow}>
          <div className={styles.networkNode}>
            <span className={styles.networkLabel}>From</span>
            <span className={styles.networkValue}>
              {currentNetworkIcon} {currentNetwork?.name || "Unknown Network"}
            </span>
          </div>
          <Tooltip content="Your tokens will be locked on the source chain and released on the destination chain">
            <div className={styles.arrow}>
              <span className={styles.arrowIcon}>→</span>
              <span className={styles.arrowLabel}>CCIP</span>
            </div>
          </Tooltip>
          <div className={styles.networkNode}>
            <span className={styles.networkLabel}>To</span>
            <span className={styles.networkValue}>
              {getDestNetworkIcon(destChainSelector)}{" "}
              {getDestNetworkName(destChainSelector)}
            </span>
          </div>
        </div>

        {/* Liquidity Info */}
        <div className={styles.liquidityInfo}>
          <span className={styles.liquidityLabel}>
            Bridge Liquidity:
            <InfoIcon
              tooltip="Available GLD tokens in the bridge contract on the destination chain. Transfers cannot exceed this amount."
              size="sm"
            />
          </span>
          <span className={styles.liquidityValue}>
            {parseFloat(bridgeBalance).toFixed(4)} GLD
          </span>
        </div>

        {error && (
          <Alert type="error" className="mb-4" onClose={() => {}}>
            {error}
          </Alert>
        )}

        {successMsg && (
          <Alert
            type="success"
            className="mb-4"
            onClose={() => setSuccessMsg(null)}
          >
            {successMsg}
          </Alert>
        )}

        {/* Bridge Form */}
        <div className="flex flex-col gap-4">
          <Input
            label={
              <span className={styles.inputLabel}>
                Receiver Address
                <InfoIcon
                  tooltip="The address that will receive the tokens on the destination chain. Defaults to your current address."
                  size="sm"
                />
              </span>
            }
            placeholder="0x..."
            value={receiver}
            onChange={(e) => setReceiver(e.target.value)}
          />

          <Input
            label={
              <span className={styles.inputLabel}>
                Amount (GLD)
                <InfoIcon
                  tooltip="The amount of GLD tokens to bridge. Must not exceed bridge liquidity."
                  size="sm"
                />
              </span>
            }
            placeholder="0.0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            type="number"
            min="0"
            step="0.0001"
            rightElement="GLD"
          />

          <div className={styles.feeSelection}>
            <label className={styles.feeLabel}>
              Pay Bridge Fees In:
              <InfoIcon
                tooltip={
                  <span>
                    <strong>Native Token:</strong> Pay with ETH or BNB
                    <br />
                    <strong>LINK:</strong> Pay with Chainlink tokens (often
                    cheaper)
                  </span>
                }
                size="sm"
              />
            </label>
            <div className={styles.radioGroup}>
              <label className={styles.radioLabel}>
                <input
                  type="radio"
                  name="feeType"
                  checked={payFeesIn === PayFeesIn.Native}
                  onChange={() => setPayFeesIn(PayFeesIn.Native)}
                />
                <span className={styles.radioText}>
                  {currentNetworkIcon} Native (
                  {currentNetwork?.currency || "ETH/BNB"})
                </span>
              </label>
              <label className={styles.radioLabel}>
                <input
                  type="radio"
                  name="feeType"
                  checked={payFeesIn === PayFeesIn.LINK}
                  onChange={() => setPayFeesIn(PayFeesIn.LINK)}
                />
                <span className={styles.radioText}>🔗 LINK</span>
              </label>
            </div>
          </div>

          <Button
            onClick={handleBridge}
            isLoading={loading}
            disabled={
              !isConnected ||
              isPaused ||
              !receiver ||
              !amount ||
              parseFloat(amount) <= 0
            }
            fullWidth
          >
            🌉 Bridge Tokens
          </Button>
        </div>

        {/* Info Note */}
        <div className={styles.infoNote}>
          <HighlightBox variant="info">
            <strong>⏱️ Transfer Time:</strong> Bridge transfers typically take
            15-30 minutes to complete via Chainlink CCIP. You can track your
            transfer on the destination chain's block explorer.
          </HighlightBox>
        </div>

        {/* Toggle Education */}
        <button
          className={styles.toggleEducation}
          onClick={() => setShowEducation(!showEducation)}
        >
          {showEducation ? "Hide" : "Show"} explanations
        </button>
      </Card.Body>
    </Card>
  );
};
