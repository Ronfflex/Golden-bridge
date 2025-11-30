import React from "react";
import styles from "./StepIndicator.module.css";

export interface Step {
  id: string;
  label: string;
  icon: string;
  description?: string;
}

interface StepIndicatorProps {
  steps: Step[];
  currentStep: string;
  completedSteps: string[];
  onStepClick?: (stepId: string) => void;
  className?: string;
}

export const StepIndicator: React.FC<StepIndicatorProps> = ({
  steps,
  currentStep,
  completedSteps,
  onStepClick,
  className = "",
}) => {
  const getStepStatus = (
    stepId: string
  ): "completed" | "current" | "upcoming" => {
    if (completedSteps.includes(stepId)) return "completed";
    if (stepId === currentStep) return "current";
    return "upcoming";
  };

  return (
    <div className={`${styles.stepIndicator} ${className}`}>
      {steps.map((step, index) => {
        const status = getStepStatus(step.id);
        const isClickable =
          onStepClick && (status === "completed" || status === "current");

        return (
          <React.Fragment key={step.id}>
            <div
              className={`${styles.step} ${styles[status]} ${
                isClickable ? styles.clickable : ""
              }`}
              onClick={isClickable ? () => onStepClick(step.id) : undefined}
            >
              <div className={styles.stepIcon}>
                {status === "completed" ? (
                  <span className={styles.checkmark}>✓</span>
                ) : (
                  <span>{step.icon}</span>
                )}
              </div>
              <div className={styles.stepContent}>
                <span className={styles.stepLabel}>{step.label}</span>
                {step.description && (
                  <span className={styles.stepDescription}>
                    {step.description}
                  </span>
                )}
              </div>
            </div>
            {index < steps.length - 1 && (
              <div
                className={`${styles.connector} ${
                  completedSteps.includes(step.id)
                    ? styles.connectorCompleted
                    : ""
                }`}
              />
            )}
          </React.Fragment>
        );
      })}
    </div>
  );
};

// Compact horizontal version for header
interface CompactStepIndicatorProps {
  steps: Step[];
  currentStep: string;
  completedSteps: string[];
  className?: string;
}

export const CompactStepIndicator: React.FC<CompactStepIndicatorProps> = ({
  steps,
  currentStep,
  completedSteps,
  className = "",
}) => {
  const getStepStatus = (
    stepId: string
  ): "completed" | "current" | "upcoming" => {
    if (completedSteps.includes(stepId)) return "completed";
    if (stepId === currentStep) return "current";
    return "upcoming";
  };

  return (
    <div className={`${styles.compactIndicator} ${className}`}>
      {steps.map((step, index) => {
        const status = getStepStatus(step.id);

        return (
          <React.Fragment key={step.id}>
            <div
              className={`${styles.compactStep} ${styles[`compact-${status}`]}`}
            >
              <span className={styles.compactIcon}>
                {status === "completed" ? "✓" : step.icon}
              </span>
              <span className={styles.compactLabel}>{step.label}</span>
            </div>
            {index < steps.length - 1 && (
              <div
                className={`${styles.compactConnector} ${
                  completedSteps.includes(step.id)
                    ? styles.compactConnectorCompleted
                    : ""
                }`}
              />
            )}
          </React.Fragment>
        );
      })}
    </div>
  );
};
