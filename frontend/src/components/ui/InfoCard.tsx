import React, { useState } from "react";
import styles from "./InfoCard.module.css";

interface InfoCardProps {
  title: string;
  icon?: string;
  children: React.ReactNode;
  variant?: "default" | "highlight" | "warning" | "success";
  collapsible?: boolean;
  defaultExpanded?: boolean;
  className?: string;
}

export const InfoCard: React.FC<InfoCardProps> = ({
  title,
  icon,
  children,
  variant = "default",
  collapsible = false,
  defaultExpanded = true,
  className = "",
}) => {
  const [isExpanded, setIsExpanded] = useState(defaultExpanded);

  return (
    <div className={`${styles.infoCard} ${styles[variant]} ${className}`}>
      <div
        className={`${styles.header} ${collapsible ? styles.clickable : ""}`}
        onClick={collapsible ? () => setIsExpanded(!isExpanded) : undefined}
      >
        <div className={styles.titleRow}>
          {icon && <span className={styles.icon}>{icon}</span>}
          <h4 className={styles.title}>{title}</h4>
        </div>
        {collapsible && (
          <span
            className={`${styles.chevron} ${isExpanded ? styles.expanded : ""}`}
          >
            ▼
          </span>
        )}
      </div>
      {(!collapsible || isExpanded) && (
        <div className={styles.content}>{children}</div>
      )}
    </div>
  );
};

// Feature list item for use within InfoCard
interface FeatureItemProps {
  icon?: string;
  title: string;
  description: string;
}

export const FeatureItem: React.FC<FeatureItemProps> = ({
  icon = "•",
  title,
  description,
}) => {
  return (
    <div className={styles.featureItem}>
      <span className={styles.featureIcon}>{icon}</span>
      <div className={styles.featureContent}>
        <span className={styles.featureTitle}>{title}</span>
        <span className={styles.featureDescription}>{description}</span>
      </div>
    </div>
  );
};

// Highlight box for important information
interface HighlightBoxProps {
  children: React.ReactNode;
  variant?: "info" | "warning" | "success" | "gold";
  className?: string;
}

export const HighlightBox: React.FC<HighlightBoxProps> = ({
  children,
  variant = "info",
  className = "",
}) => {
  return (
    <div
      className={`${styles.highlightBox} ${
        styles[`highlight-${variant}`]
      } ${className}`}
    >
      {children}
    </div>
  );
};
