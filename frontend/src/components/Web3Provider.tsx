import { ReactNode } from "react";
// Importing the config initializes the AppKit
import "../config/reown";

interface Props {
  children: ReactNode;
}

export function Web3Provider({ children }: Props) {
  return <>{children}</>;
}
