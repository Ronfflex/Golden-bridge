import { useAppKitAccount } from "@reown/appkit/react";
import { formatEther } from "ethers";
import React, { useEffect, useMemo, useState } from "react";
import { useAdmin } from "../../hooks/useAdmin";
import { useGoldToken } from "../../hooks/useGoldToken";
import { useNetwork } from "../../hooks/useNetwork";
import { AdminPanel } from "../Admin/AdminPanel";
import { GoldTokenCard } from "../GoldToken/GoldTokenCard";
import { LotterieCard } from "../Lotterie/LotterieCard";
import { NetworkSwitcher } from "../NetworkSwitcher";
import { TokenBridgeCard } from "../TokenBridge/TokenBridgeCard";
import { Alert } from "../ui/Alert";
import { Badge } from "../ui/Badge";
import { FeatureItem, HighlightBox, InfoCard } from "../ui/InfoCard";
import { CompactStepIndicator, Step } from "../ui/StepIndicator";
import { InfoIcon, Tooltip } from "../ui/Tooltip";
import styles from "./Dashboard.module.css";

// Define the user journey steps
const JOURNEY_STEPS: Step[] = [
  {
    id: "connect",
    label: "Connect Wallet",
    icon: "🔗",
    description: "Connect your Web3 wallet to get started",
  },
  {
    id: "mint",
    label: "Mint GLD",
    icon: "🪙",
    description: "Convert ETH to gold-backed GLD tokens",
  },
  {
    id: "lottery",
    label: "Lottery",
    icon: "🎰",
    description: "Participate in daily draws with your GLD",
  },
  {
    id: "bridge",
    label: "Bridge",
    icon: "🌉",
    description: "Transfer GLD across chains (optional)",
  },
];

export const Dashboard: React.FC = () => {
  const { isConnected, address } = useAppKitAccount();
  const { isSupportedNetwork } = useNetwork();
  const { balanceOf } = useGoldToken();
  const { isAnyOwner } = useAdmin();

  const [balance, setBalance] = useState<string>("0");
  const [showOnboarding, setShowOnboarding] = useState(true);

  // Fetch user balance to determine step progress
  useEffect(() => {
    const fetchBalance = async () => {
      if (isConnected && address) {
        try {
          const bal = await balanceOf(address);
          setBalance(formatEther(bal));
        } catch (err) {
          console.error("Error fetching balance:", err);
        }
      }
    };
    fetchBalance();
  }, [isConnected, address, balanceOf]);

  // Compute step progress based on user state (using useMemo to avoid cascading renders)
  const { currentStep, completedSteps } = useMemo(() => {
    const completed: string[] = [];
    let current = "connect";

    if (isConnected) {
      completed.push("connect");
      current = "mint";

      if (parseFloat(balance) > 0) {
        completed.push("mint");
        current = "lottery";

        if (parseFloat(balance) >= 1) {
          completed.push("lottery");
          current = "bridge";
        }
      }
    }

    return { currentStep: current, completedSteps: completed };
  }, [isConnected, balance]);

  // Welcome screen for non-connected users
  if (!isConnected) {
    return (
      <div className={styles.container}>
        <div className={styles.welcome}>
          <div className={styles.welcomeHeader}>
            <h1 className={styles.title}>🏆 Welcome to Golden Bridge</h1>
            <p className={styles.subtitle}>
              Your gateway to gold-backed tokens on the blockchain
            </p>
          </div>

          {/* Value Proposition */}
          <div className={styles.valueProps}>
            <HighlightBox variant="gold">
              <strong>1 GLD = 1 gram of gold</strong>
              <br />
              Hold tokenized gold backed by real-time Chainlink price feeds
            </HighlightBox>
          </div>

          {/* Feature Cards */}
          <div className={styles.features}>
            <div className={styles.feature}>
              <span className={styles.featureIcon}>🪙</span>
              <h3>Gold Token</h3>
              <p>
                Mint GLD tokens backed by real-time gold prices using Chainlink
                Price Feeds.
              </p>
              <Badge variant="info">Chainlink Powered</Badge>
            </div>
            <div className={styles.feature}>
              <span className={styles.featureIcon}>🎰</span>
              <h3>Daily Lottery</h3>
              <p>
                Win rewards from transaction fees in provably fair daily draws.
              </p>
              <Badge variant="success">VRF Secured</Badge>
            </div>
            <div className={styles.feature}>
              <span className={styles.featureIcon}>🌉</span>
              <h3>Cross-Chain Bridge</h3>
              <p>Seamlessly transfer GLD between Ethereum and BSC networks.</p>
              <Badge variant="warning">CCIP Enabled</Badge>
            </div>
          </div>

          {/* How It Works */}
          <InfoCard
            title="How It Works"
            icon="📚"
            variant="default"
            collapsible
            defaultExpanded={false}
          >
            <FeatureItem
              icon="1️⃣"
              title="Connect Your Wallet"
              description="Use MetaMask or any Web3 wallet to connect to the dApp"
            />
            <FeatureItem
              icon="2️⃣"
              title="Mint GLD Tokens"
              description="Send ETH to receive GLD at the current gold price (5% fee applies)"
            />
            <FeatureItem
              icon="3️⃣"
              title="Participate in Lottery"
              description="Hold at least 1 GLD to be eligible for daily lottery draws"
            />
            <FeatureItem
              icon="4️⃣"
              title="Bridge Across Chains"
              description="Transfer your GLD between Ethereum and BSC using Chainlink CCIP"
            />
          </InfoCard>

          {/* Technology Stack */}
          <div className={styles.techStack}>
            <h4 className={styles.techTitle}>
              Powered by Chainlink
              <InfoIcon
                tooltip="Golden Bridge uses multiple Chainlink services for security and reliability"
                size="md"
              />
            </h4>
            <div className={styles.techItems}>
              <Tooltip content="Real-time gold and ETH prices from decentralized oracles">
                <div className={styles.techItem}>
                  <span>📊</span>
                  <span>Price Feeds</span>
                </div>
              </Tooltip>
              <Tooltip content="Verifiable random numbers for fair lottery selection">
                <div className={styles.techItem}>
                  <span>🎲</span>
                  <span>VRF</span>
                </div>
              </Tooltip>
              <Tooltip content="Secure cross-chain messaging for token bridging">
                <div className={styles.techItem}>
                  <span>🔗</span>
                  <span>CCIP</span>
                </div>
              </Tooltip>
            </div>
          </div>

          {/* Connect CTA */}
          <div className={styles.connectCta}>
            <p className={styles.ctaText}>
              Connect your wallet to start your golden journey
            </p>
            <appkit-button />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      {/* Header with Step Indicator */}
      <div className={styles.header}>
        <div className={styles.headerLeft}>
          <h1 className={styles.title}>🏆 Dashboard</h1>
          <p className={styles.subtitle}>Manage your Golden Bridge assets</p>
        </div>
        <div className={styles.headerRight}>
          <NetworkSwitcher />
        </div>
      </div>

      {/* Progress Indicator */}
      <div className={styles.progressSection}>
        <CompactStepIndicator
          steps={JOURNEY_STEPS}
          currentStep={currentStep}
          completedSteps={completedSteps}
        />
      </div>

      {/* Network Warning */}
      {!isSupportedNetwork() && (
        <Alert type="warning" title="Unsupported Network" className="mb-4">
          Please switch to Sepolia Testnet or BSC Testnet to use the
          application.
        </Alert>
      )}

      {/* Onboarding Tips */}
      {showOnboarding && completedSteps.length < 3 && (
        <div className={styles.onboardingSection}>
          <InfoCard
            title="🎯 Getting Started"
            icon=""
            variant="highlight"
            collapsible
            defaultExpanded={true}
          >
            {currentStep === "mint" && (
              <>
                <p>
                  <strong>Next Step:</strong> Mint your first GLD tokens!
                </p>
                <HighlightBox variant="gold">
                  Enter an ETH amount in the Gold Token card below and click
                  "Mint GLD" to convert your ETH to gold-backed tokens.
                </HighlightBox>
              </>
            )}
            {currentStep === "lottery" && (
              <>
                <p>
                  <strong>Great progress!</strong> You now own GLD tokens.
                </p>
                <HighlightBox variant="info">
                  {parseFloat(balance) >= 1 ? (
                    <>
                      ✅ You're eligible for the lottery! Check the Lottery card
                      to see your pending rewards.
                    </>
                  ) : (
                    <>
                      Hold at least 1 GLD to become eligible for daily lottery
                      draws. You currently have {parseFloat(balance).toFixed(4)}{" "}
                      GLD.
                    </>
                  )}
                </HighlightBox>
              </>
            )}
            {currentStep === "bridge" && (
              <>
                <p>
                  <strong>You're all set!</strong> You can now bridge your GLD
                  to other chains.
                </p>
                <HighlightBox variant="success">
                  Use the Bridge card to transfer GLD between Ethereum and BSC.
                  This is optional but useful for accessing different DeFi
                  ecosystems.
                </HighlightBox>
              </>
            )}
            <button
              className={styles.dismissOnboarding}
              onClick={() => setShowOnboarding(false)}
            >
              Dismiss tips
            </button>
          </InfoCard>
        </div>
      )}

      {/* Admin Panel - Only visible to owners */}
      {isAnyOwner && (
        <div className={styles.adminSection}>
          <AdminPanel />
        </div>
      )}

      {/* Main Content Grid */}
      <div className={styles.grid}>
        <div className={styles.mainColumn}>
          <GoldTokenCard />
        </div>
        <div className={styles.sideColumn}>
          <div className={styles.sideItem}>
            <LotterieCard />
          </div>
          <div className={styles.sideItem}>
            <TokenBridgeCard />
          </div>
        </div>
      </div>

      {/* Footer Info */}
      <div className={styles.footer}>
        <div className={styles.footerContent}>
          <span className={styles.footerText}>
            Golden Bridge - A Chainlink-powered DeFi showcase
          </span>
          <div className={styles.footerLinks}>
            <Tooltip content="View smart contracts on GitHub">
              <a
                href="https://github.com/Ronfflex/Golden-bridge"
                target="_blank"
                rel="noopener noreferrer"
                className={styles.footerLink}
              >
                📂 Source Code
              </a>
            </Tooltip>
          </div>
        </div>
      </div>
    </div>
  );
};
