import { Dashboard } from "./components/Dashboard/Dashboard";
import { WalletConnect } from "./components/WalletConnect";
import "./styles/globals.css";

function App() {
  return (
    <div className="app-container">
      <header
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          padding: "1rem 2rem",
          borderBottom: "1px solid var(--color-border)",
          backgroundColor: "var(--color-surface)",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
          <h1
            style={{
              fontSize: "1.5rem",
              fontWeight: "bold",
              color: "var(--color-primary)",
            }}
          >
            Golden Bridge
          </h1>
        </div>
        <WalletConnect />
      </header>

      <main>
        <Dashboard />
      </main>
    </div>
  );
}

export default App;
