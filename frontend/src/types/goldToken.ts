export interface GoldTokenEvents {
  FeesAddressUpdated: {
    previousFeesAddress: string;
    newFeesAddress: string;
  };
  GoldTokenInitialized: {
    owner: string;
    dataFeedGold: string;
    dataFeedEth: string;
  };
  LotterieAddressUpdated: {
    previousLotterieAddress: string;
    newLotterieAddress: string;
  };
  Mint: {
    to: string;
    amount: bigint;
  };
  UserAdded: {
    user: string;
    timestamp: bigint;
  };
  UserRemoved: {
    user: string;
  };
}

export interface GoldTokenFunctions {
  // User-Facing
  mint: (value: bigint) => Promise<void>;
  burn: (amount: bigint) => Promise<void>;
  transfer: (to: string, amount: bigint) => Promise<boolean>;
  balanceOf: (account: string) => Promise<bigint>;
  claimEth: () => Promise<void>;

  // View Functions
  getGoldPriceInEth: () => Promise<bigint>;
  getFees: () => Promise<bigint>;
  getFeesAddress: () => Promise<string>;
  getUsers: () => Promise<string[]>;
  getTimestamps: () => Promise<{ users: string[]; timestamps: bigint[] }>;
  hasOwnerRole: (account: string) => Promise<boolean>;

  // Admin Functions
  setFeesAddress: (feesAddress: string) => Promise<void>;
  setLotterieAddress: (lotterieAddress: string) => Promise<void>;
  addOwner: (account: string) => Promise<void>;
  removeOwner: (account: string) => Promise<void>;
  pause: () => Promise<void>;
  unpause: () => Promise<void>;
}
