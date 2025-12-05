# Golden Bridge Frontend

This is the frontend application for the Golden Bridge project, a gold-backed tokenization platform with lottery rewards and cross-chain bridging capabilities.

## Project Description

The Golden Bridge frontend allows users to:

- Connect their wallet (MetaMask, WalletConnect, etc.)
- Mint and burn Gold Tokens (GLD)
- Participate in the daily lottery
- Bridge tokens between Ethereum Sepolia and BSC Testnet
- View their token balance and transaction history

## Setup Instructions

1. **Prerequisites:**

   - Node.js (v18 or later)
   - npm or yarn

2. **Installation:**

   ```bash
   cd frontend
   npm install
   ```

3. **Environment Configuration:**

   - Copy `.env.example` to `.env`:
     ```bash
     cp .env.example .env
     ```
   - Update the `.env` file with your specific configuration values (RPC URLs, Project ID, etc.).

4. **Running the Application:**
   ```bash
   npm run dev
   ```
   The application will be available at `http://localhost:5173`.

## Environment Variables

The following environment variables are required in the `.env` file:

- `VITE_REOWN_PROJECT_ID`: Your Reown (ex WalletConnect) Project ID
- `VITE_CONTRACT_ADDRESS_SEPOLIA_GOLD_TOKEN`: Gold Token contract address on Ethereum Sepolia
- `VITE_CONTRACT_ADDRESS_SEPOLIA_LOTTERIE`: Lotterie contract address on Ethereum Sepolia
- `VITE_CONTRACT_ADDRESS_SEPOLIA_TOKEN_BRIDGE`: Token Bridge contract address on Ethereum Sepolia
- `VITE_CONTRACT_ADDRESS_BSC_TESTNET_GOLD_TOKEN`: Gold Token contract address on BSC Testnet
- `VITE_CONTRACT_ADDRESS_BSC_TESTNET_LOTTERIE`: Lotterie contract address on BSC Testnet
- `VITE_CONTRACT_ADDRESS_BSC_TESTNET_TOKEN_BRIDGE`: Token Bridge contract address on BSC Testnet
- `VITE_RPC_URL_SEPOLIA`: RPC URL for Ethereum Sepolia
- `VITE_RPC_URL_BSC_TESTNET`: RPC URL for BSC Testnet
- `VITE_SITE_NAME`: Name of the site (default: "Golden Bridge")
- `VITE_SITE_DESCRIPTION`: Description of the site
- `VITE_SITE_URL`: URL of the site
- `VITE_SITE_ICON`: URL of the site icon

## Available Scripts

- `npm run dev`: Starts the development server
- `npm run build`: Builds the application for production
- `npm run preview`: Previews the production build locally
- `npm run lint`: Runs ESLint to check for code quality issues

## Project Structure

- `src/components`: React components
  - `Dashboard`: Main dashboard component
  - `GoldToken`: Components related to Gold Token operations
  - `Lotterie`: Components related to the lottery
  - `TokenBridge`: Components related to the bridge
  - `ui`: Reusable UI components
- `src/config`: Configuration files (contracts, networks, etc.)
- `src/hooks`: Custom React hooks
- `src/styles`: Global styles and CSS modules
- `src/types`: TypeScript type definitions
- `src/utils`: Utility functions
- `abi`: Smart contract ABIs

## Technologies Used

- React
- TypeScript
- Vite
- ethers.js
- Reown AppKit (WalletConnect)
- CSS Modules
