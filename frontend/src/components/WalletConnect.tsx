import { useAppKitAccount } from "@reown/appkit/react";

export function WalletConnect() {
  const { isConnected } = useAppKitAccount();

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        gap: "10px",
        alignItems: "flex-end",
      }}
    >
      <div style={{ display: "flex", gap: "10px", alignItems: "center" }}>
        {isConnected}
        {/* Reown's built-in button handles connection, network switching, and account view */}
        <appkit-button />
      </div>
    </div>
  );
}
