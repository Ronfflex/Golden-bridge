import React, { useRef, useState } from "react";
import styles from "./Tooltip.module.css";

interface TooltipProps {
  content: React.ReactNode;
  children: React.ReactNode;
  position?: "top" | "bottom" | "left" | "right";
  className?: string;
}

export const Tooltip: React.FC<TooltipProps> = ({
  content,
  children,
  position = "top",
  className = "",
}) => {
  const [isVisible, setIsVisible] = useState(false);
  const tooltipRef = useRef<HTMLDivElement>(null);

  return (
    <div
      className={`${styles.tooltipWrapper} ${className}`}
      onMouseEnter={() => setIsVisible(true)}
      onMouseLeave={() => setIsVisible(false)}
      ref={tooltipRef}
    >
      {children}
      {isVisible && (
        <div className={`${styles.tooltip} ${styles[position]}`}>
          <div className={styles.tooltipContent}>{content}</div>
          <div className={styles.arrow} />
        </div>
      )}
    </div>
  );
};

// Info icon component for use with tooltips
interface InfoIconProps {
  tooltip: React.ReactNode;
  size?: "sm" | "md" | "lg";
  className?: string;
}

export const InfoIcon: React.FC<InfoIconProps> = ({
  tooltip,
  size = "md",
  className = "",
}) => {
  return (
    <Tooltip content={tooltip} position="top">
      <span
        className={`${styles.infoIcon} ${styles[`icon-${size}`]} ${className}`}
      >
        ℹ️
      </span>
    </Tooltip>
  );
};
