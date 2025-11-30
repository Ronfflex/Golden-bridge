import { formatEther, formatUnits, parseEther } from "ethers";
import React, { useEffect, useState } from "react";
import { useGoldToken } from "../../hooks/useGoldToken";
import { Alert } from "../ui/Alert";
import { Badge } from "../ui/Badge";
import { Button } from "../ui/Button";
import { Card } from "../ui/Card";
import { FeatureItem, HighlightBox, InfoCard } from "../ui/InfoCard";
import { Input } from "../ui/Input";
import { InfoIcon, Tooltip } from "../ui/Tooltip";
import styles from "./GoldTokenCard.module.css";

export const GoldTokenCard: React.FC = () => {
  const {
    loading,
    error,
    isConnected,
    address,
    mint,
    burn,
    transfer,
    balanceOf,
    getGoldPriceInEth,
    getFees,
  } = useGoldToken();

  const [balance, setBalance] = useState<string>("0");
  const [goldPrice, setGoldPrice] = useState<string>("0");
  const [fees, setFees] = useState<string>("0");
  const [mintAmount, setMintAmount] = useState("");
  const [burnAmount, setBurnAmount] = useState("");
  const [transferTo, setTransferTo] = useState("");
  const [transferAmount, setTransferAmount] = useState("");
  const [activeTab, setActiveTab] = useState<"mint" | "burn" | "transfer">(
    "mint"
  );
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [showEducation, setShowEducation] = useState(true);

  const fetchData = async () => {
    try {
      if (address) {
        const bal = await balanceOf(address);
        setBalance(formatEther(bal));
      }
      const price = await getGoldPriceInEth();
      setGoldPrice(formatUnits(price, 8));

      const fee = await getFees();
      setFees(fee.toString());
    } catch (err) {
      console.error("Error fetching data:", err);
    }
  };

  useEffect(() => {
    if (isConnected && address) {
      fetchData();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConnected, address]);

  const handleMint = async () => {
    try {
      setSuccessMsg(null);
      if (!mintAmount) return;
      await mint(parseEther(mintAmount));
      setSuccessMsg(`Successfully minted GLD with ${mintAmount} ETH!`);
      setMintAmount("");
      fetchData();
    } catch (err) {
      console.error(err);
    }
  };

  const handleBurn = async () => {
    try {
      setSuccessMsg(null);
      if (!burnAmount) return;
      await burn(parseEther(burnAmount));
      setSuccessMsg(`Successfully burned ${burnAmount} GLD!`);
      setBurnAmount("");
      fetchData();
    } catch (err) {
      console.error(err);
    }
  };

  const handleTransfer = async () => {
    try {
      setSuccessMsg(null);
      if (!transferTo || !transferAmount) return;
      await transfer(transferTo, parseEther(transferAmount));
      setSuccessMsg(
        `Successfully transferred ${transferAmount} GLD to ${transferTo.substring(
          0,
          6
        )}...${transferTo.substring(38)}!`
      );
      setTransferTo("");
      setTransferAmount("");
      fetchData();
    } catch (err) {
      console.error(err);
    }
  };

  const estimatedGld =
    mintAmount && goldPrice && parseFloat(goldPrice) > 0
      ? (parseFloat(mintAmount) / parseFloat(goldPrice)).toFixed(4)
      : "0";

  const feeAmount =
    mintAmount && parseFloat(mintAmount) > 0
      ? ((parseFloat(mintAmount) * parseFloat(fees)) / 100).toFixed(6)
      : "0";

  const isEligible = parseFloat(balance) >= 1;

  return (
    <Card className={styles.card}>
      <Card.Header
        title={
          <span className={styles.headerTitle}>
            🪙 Gold Token (GLD)
            <InfoIcon
              tooltip={
                <span>
                  <strong>1 GLD = 1 gram of gold</strong>
                  <br />
                  GLD is an ERC-20 token backed by real-time gold prices from
                  Chainlink Price Feeds.
                </span>
              }
              size="md"
            />
          </span>
        }
        subtitle="Mint, burn, and transfer gold-backed tokens"
        action={
          <Tooltip
            content={
              isEligible
                ? "You're eligible for the daily lottery! Hold at least 1 GLD to participate."
                : "Hold at least 1 GLD to become eligible for the daily lottery."
            }
          >
            <Badge variant={isEligible ? "success" : "secondary"}>
              {isEligible ? "✓ Lottery Eligible" : "Not Eligible"}
            </Badge>
          </Tooltip>
        }
      />
      <Card.Body>
        {/* Stats Section */}
        <div className={styles.statsGrid}>
          <div className={styles.statItem}>
            <span className={styles.statLabel}>
              Your Balance
              <InfoIcon
                tooltip="Your current GLD token balance on this network"
                size="sm"
              />
            </span>
            <span className={styles.statValue}>
              {parseFloat(balance).toFixed(4)} GLD
            </span>
          </div>
          <div className={styles.statItem}>
            <span className={styles.statLabel}>
              Gold Price
              <InfoIcon
                tooltip={
                  <span>
                    Current price of 1 gram of gold in ETH.
                    <br />
                    <em>Powered by Chainlink Price Feeds</em>
                  </span>
                }
                size="sm"
              />
            </span>
            <span className={styles.statValue}>
              {parseFloat(goldPrice).toFixed(6)} ETH
            </span>
          </div>
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

        {/* Tabs */}
        <div className={styles.tabs}>
          <button
            className={`${styles.tab} ${
              activeTab === "mint" ? styles.activeTab : ""
            }`}
            onClick={() => setActiveTab("mint")}
          >
            <span className={styles.tabIcon}>🟢</span> Mint
          </button>
          <button
            className={`${styles.tab} ${
              activeTab === "burn" ? styles.activeTab : ""
            }`}
            onClick={() => setActiveTab("burn")}
          >
            <span className={styles.tabIcon}>🔴</span> Burn
          </button>
          <button
            className={`${styles.tab} ${
              activeTab === "transfer" ? styles.activeTab : ""
            }`}
            onClick={() => setActiveTab("transfer")}
          >
            <span className={styles.tabIcon}>📤</span> Transfer
          </button>
        </div>

        <div className={styles.tabContent}>
          {/* MINT TAB */}
          {activeTab === "mint" && (
            <div className="flex flex-col gap-4">
              {showEducation && (
                <InfoCard
                  title="What is Minting?"
                  icon="💡"
                  collapsible
                  defaultExpanded={true}
                >
                  <p>
                    <strong>Minting</strong> converts your ETH into GLD tokens
                    at the current gold price. Each GLD represents 1 gram of
                    gold.
                  </p>
                  <HighlightBox variant="gold">
                    <strong>How it works:</strong>
                    <br />
                    1. Enter the amount of ETH you want to spend
                    <br />
                    2. The contract calculates how much GLD you'll receive based
                    on real-time gold prices
                    <br />
                    3. A 5% fee is applied (split between lottery pool and
                    treasury)
                  </HighlightBox>
                  <FeatureItem
                    icon="📊"
                    title="Chainlink Price Feeds"
                    description="Gold prices are fetched from Chainlink's decentralized oracle network, ensuring accurate and tamper-proof pricing."
                  />
                </InfoCard>
              )}

              <Input
                label={
                  <span className={styles.inputLabel}>
                    Amount (ETH)
                    <InfoIcon
                      tooltip="Enter the amount of ETH you want to convert to GLD"
                      size="sm"
                    />
                  </span>
                }
                placeholder="0.0"
                value={mintAmount}
                onChange={(e) => setMintAmount(e.target.value)}
                type="number"
                min="0"
                step="0.0001"
                rightElement="ETH"
              />

              <div className={styles.calculationBox}>
                <div className={styles.calcRow}>
                  <span>You'll receive (estimated):</span>
                  <span className={styles.calcValue}>{estimatedGld} GLD</span>
                </div>
                <div className={styles.calcRow}>
                  <span>
                    Fee ({fees}%):
                    <InfoIcon
                      tooltip={
                        <span>
                          <strong>Fee breakdown:</strong>
                          <br />• 2.5% → Lottery Pool 🎰
                          <br />• 2.5% → Treasury 🏦
                        </span>
                      }
                      size="sm"
                    />
                  </span>
                  <span className={styles.calcFee}>{feeAmount} ETH</span>
                </div>
              </div>

              <Button
                onClick={handleMint}
                isLoading={loading}
                disabled={
                  !isConnected || !mintAmount || parseFloat(mintAmount) <= 0
                }
                fullWidth
              >
                🪙 Mint GLD
              </Button>
            </div>
          )}

          {/* BURN TAB */}
          {activeTab === "burn" && (
            <div className="flex flex-col gap-4">
              {showEducation && (
                <InfoCard
                  title="What is Burning?"
                  icon="🔥"
                  collapsible
                  defaultExpanded={true}
                >
                  <p>
                    <strong>Burning</strong> destroys your GLD tokens, removing
                    them from circulation. This is how you exit your gold
                    position.
                  </p>
                  <HighlightBox variant="warning">
                    <strong>⚠️ Important:</strong> Burning is irreversible. Once
                    burned, tokens cannot be recovered. A 5% fee applies to burn
                    operations.
                  </HighlightBox>
                  <FeatureItem
                    icon="📉"
                    title="Reduce Supply"
                    description="Burning tokens decreases the total supply, which can affect the token's scarcity."
                  />
                </InfoCard>
              )}

              <Input
                label={
                  <span className={styles.inputLabel}>
                    Amount (GLD)
                    <InfoIcon
                      tooltip="Enter the amount of GLD tokens you want to burn"
                      size="sm"
                    />
                  </span>
                }
                placeholder="0.0"
                value={burnAmount}
                onChange={(e) => setBurnAmount(e.target.value)}
                type="number"
                min="0"
                step="0.0001"
                rightElement="GLD"
              />

              <div className={styles.calculationBox}>
                <div className={styles.calcRow}>
                  <span>Your balance:</span>
                  <span className={styles.calcValue}>
                    {parseFloat(balance).toFixed(4)} GLD
                  </span>
                </div>
                <div className={styles.calcRow}>
                  <span>Fee ({fees}%):</span>
                  <span className={styles.calcFee}>
                    {burnAmount
                      ? (
                          (parseFloat(burnAmount) * parseFloat(fees)) /
                          100
                        ).toFixed(4)
                      : "0"}{" "}
                    GLD
                  </span>
                </div>
              </div>

              <Button
                variant="danger"
                onClick={handleBurn}
                isLoading={loading}
                disabled={
                  !isConnected || !burnAmount || parseFloat(burnAmount) <= 0
                }
                fullWidth
              >
                🔥 Burn GLD
              </Button>
            </div>
          )}

          {/* TRANSFER TAB */}
          {activeTab === "transfer" && (
            <div className="flex flex-col gap-4">
              {showEducation && (
                <InfoCard
                  title="Transfer Tokens"
                  icon="📤"
                  collapsible
                  defaultExpanded={true}
                >
                  <p>
                    Send GLD tokens to another wallet address. Transfers are
                    instant and recorded on the blockchain.
                  </p>
                  <HighlightBox variant="info">
                    <strong>💡 Tip:</strong> Double-check the recipient address
                    before sending. Blockchain transactions cannot be reversed!
                  </HighlightBox>
                  <FeatureItem
                    icon="🎰"
                    title="Lottery Eligibility"
                    description="Receiving GLD may make you eligible for the daily lottery if your balance reaches 1 GLD."
                  />
                </InfoCard>
              )}

              <Input
                label={
                  <span className={styles.inputLabel}>
                    Recipient Address
                    <InfoIcon
                      tooltip="The Ethereum address that will receive the GLD tokens"
                      size="sm"
                    />
                  </span>
                }
                placeholder="0x..."
                value={transferTo}
                onChange={(e) => setTransferTo(e.target.value)}
              />
              <Input
                label="Amount (GLD)"
                placeholder="0.0"
                value={transferAmount}
                onChange={(e) => setTransferAmount(e.target.value)}
                type="number"
                min="0"
                step="0.0001"
                rightElement="GLD"
              />

              <div className={styles.calculationBox}>
                <div className={styles.calcRow}>
                  <span>Your balance:</span>
                  <span className={styles.calcValue}>
                    {parseFloat(balance).toFixed(4)} GLD
                  </span>
                </div>
                <div className={styles.calcRow}>
                  <span>Remaining after transfer:</span>
                  <span className={styles.calcValue}>
                    {transferAmount
                      ? Math.max(
                          0,
                          parseFloat(balance) - parseFloat(transferAmount)
                        ).toFixed(4)
                      : parseFloat(balance).toFixed(4)}{" "}
                    GLD
                  </span>
                </div>
              </div>

              <Button
                variant="secondary"
                onClick={handleTransfer}
                isLoading={loading}
                disabled={
                  !isConnected ||
                  !transferTo ||
                  !transferAmount ||
                  parseFloat(transferAmount) <= 0
                }
                fullWidth
              >
                📤 Transfer
              </Button>
            </div>
          )}
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
