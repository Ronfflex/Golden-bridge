import { formatEther } from "ethers";
import React, { useEffect, useState } from "react";
import { useLotterie } from "../../hooks/useLotterie";
import { Alert } from "../ui/Alert";
import { Badge } from "../ui/Badge";
import { Button } from "../ui/Button";
import { Card } from "../ui/Card";
import { FeatureItem, HighlightBox, InfoCard } from "../ui/InfoCard";
import { InfoIcon, Tooltip } from "../ui/Tooltip";
import styles from "./LotterieCard.module.css";

export const LotterieCard: React.FC = () => {
  const {
    loading,
    error,
    isConnected,
    address,
    claim,
    getGains,
    getLastRequestId,
    getResults,
    getVrfSubscriptionId,
    getVrfCoordinator,
    getKeyHash,
  } = useLotterie();

  const [gains, setGains] = useState<string>("0");
  const [lastRequestId, setLastRequestId] = useState<string>("0");
  const [lastWinner, setLastWinner] = useState<string>("None");
  const [vrfInfo, setVrfInfo] = useState({
    subId: "0",
    coordinator: "",
    keyHash: "",
  });
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [showEducation, setShowEducation] = useState(true);

  const fetchData = async () => {
    try {
      if (address) {
        const userGains = await getGains(address);
        setGains(formatEther(userGains));
      }

      const reqId = await getLastRequestId();
      setLastRequestId(reqId.toString());

      if (reqId > 0n) {
        const winner = await getResults(reqId);
        setLastWinner(
          winner === "0x0000000000000000000000000000000000000000"
            ? "Pending..."
            : winner
        );
      }

      const subId = await getVrfSubscriptionId();
      const coord = await getVrfCoordinator();
      const hash = await getKeyHash();

      setVrfInfo({
        subId: subId.toString(),
        coordinator: coord,
        keyHash: hash,
      });
    } catch (err) {
      console.error("Error fetching lottery data:", err);
    }
  };

  useEffect(() => {
    if (isConnected && address) {
      fetchData();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConnected, address]);

  const handleClaim = async () => {
    try {
      setSuccessMsg(null);
      await claim();
      setSuccessMsg(`Successfully claimed ${gains} GLD!`);
      fetchData();
    } catch (err) {
      console.error(err);
    }
  };

  return (
    <Card className={styles.card}>
      <Card.Header
        title={
          <span className={styles.headerTitle}>
            🎰 Golden Lottery
            <InfoIcon
              tooltip={
                <span>
                  <strong>Daily lottery powered by Chainlink VRF</strong>
                  <br />
                  Winners are selected using verifiable random numbers, ensuring
                  complete fairness and transparency.
                </span>
              }
              size="md"
            />
          </span>
        }
        subtitle="Win rewards from transaction fees"
        action={
          <Tooltip
            content={
              <span>
                <strong>Chainlink VRF</strong> (Verifiable Random Function)
                <br />
                Provides cryptographically secure randomness that can be
                verified on-chain.
              </span>
            }
          >
            <Badge variant="info">🔗 VRF Secured</Badge>
          </Tooltip>
        }
      />
      <Card.Body>
        {/* Educational Section */}
        {showEducation && (
          <InfoCard
            title="How the Lottery Works"
            icon="🎲"
            variant="highlight"
            collapsible
            defaultExpanded={true}
          >
            <p>
              The Golden Lottery is funded by 2.5% of all mint and burn fees.
              Every day, one lucky GLD holder wins the accumulated prize pool!
            </p>
            <HighlightBox variant="gold">
              <strong>📋 Eligibility Requirements:</strong>
              <br />• Hold at least <strong>1 GLD</strong> in your wallet
              <br />
              • Your address is automatically entered when eligible
              <br />• No additional action needed to participate!
            </HighlightBox>
            <FeatureItem
              icon="🎯"
              title="Fair Selection"
              description="Winners are chosen using Chainlink VRF, which generates provably random numbers that cannot be manipulated."
            />
            <FeatureItem
              icon="⏰"
              title="Daily Draws"
              description="Draws occur once per day. The prize pool accumulates from transaction fees until the next draw."
            />
          </InfoCard>
        )}

        {/* Jackpot Section */}
        <div className={styles.jackpotSection}>
          <h4 className={styles.jackpotTitle}>
            Your Pending Rewards
            <InfoIcon
              tooltip="GLD tokens you've won and can claim. Rewards accumulate until you claim them."
              size="sm"
            />
          </h4>
          <div className={styles.jackpotValue}>
            {parseFloat(gains).toFixed(4)} GLD
          </div>
          <Button
            onClick={handleClaim}
            isLoading={loading}
            disabled={!isConnected || parseFloat(gains) <= 0}
            className="mt-4"
          >
            🎁 Claim Rewards
          </Button>
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

        {/* Last Draw Info */}
        <div className={styles.infoSection}>
          <h5 className={styles.sectionTitle}>
            📊 Last Draw Info
            <InfoIcon
              tooltip="Information about the most recent lottery draw"
              size="sm"
            />
          </h5>
          <div className={styles.infoRow}>
            <span className={styles.label}>Request ID:</span>
            <Tooltip content="Unique identifier for the VRF request">
              <span className={styles.value}>{lastRequestId}</span>
            </Tooltip>
          </div>
          <div className={styles.infoRow}>
            <span className={styles.label}>Winner:</span>
            <span className={styles.value}>
              {lastWinner !== "None" && lastWinner !== "Pending..."
                ? `${lastWinner.substring(0, 6)}...${lastWinner.substring(38)}`
                : lastWinner}
            </span>
          </div>
        </div>

        {/* VRF Configuration */}
        <div className={styles.vrfSection}>
          <h5 className={styles.sectionTitle}>
            🔐 VRF Configuration
            <InfoIcon
              tooltip={
                <span>
                  <strong>Chainlink VRF</strong> ensures fair and verifiable
                  randomness.
                  <br />
                  <br />
                  These parameters configure how random numbers are requested
                  and verified on-chain.
                </span>
              }
              size="sm"
            />
          </h5>
          <div className={styles.infoRow}>
            <span className={styles.label}>
              Subscription ID:
              <InfoIcon
                tooltip="VRF subscription that funds the randomness requests"
                size="sm"
              />
            </span>
            <span className={styles.value}>{vrfInfo.subId}</span>
          </div>
          <div className={styles.infoRow}>
            <span className={styles.label}>
              Coordinator:
              <InfoIcon
                tooltip="The Chainlink VRF Coordinator contract address"
                size="sm"
              />
            </span>
            <Tooltip content={vrfInfo.coordinator}>
              <span className={styles.value}>
                {vrfInfo.coordinator.substring(0, 10)}...
              </span>
            </Tooltip>
          </div>
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
