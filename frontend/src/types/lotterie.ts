export interface LotterieEvents {
  CallbackGasLimitUpdated: {
    previousGasLimit: number;
    newGasLimit: number;
  };
  GainClaimed: {
    account: string;
    amount: bigint;
  };
  GoldTokenUpdated: {
    previousGoldToken: string;
    newGoldToken: string;
  };
  KeyHashUpdated: {
    previousKeyHash: string;
    newKeyHash: string;
  };
  LotterieInitialized: {
    owner: string;
    vrfCoordinator: string;
    goldToken: string;
    vrfSubscriptionId: bigint;
    keyHash: string;
    callbackGasLimit: number;
    requestConfirmations: number;
    numWords: number;
  };
  NumWordsUpdated: {
    previousNumWords: number;
    newNumWords: number;
  };
  RandomDrawed: {
    requestId: bigint;
  };
  RequestConfirmationsUpdated: {
    previousConfirmations: number;
    newConfirmations: number;
  };
  VrfCoordinatorUpdated: {
    previousCoordinator: string;
    newCoordinator: string;
  };
  VrfSubscriptionUpdated: {
    previousSubscriptionId: bigint;
    newSubscriptionId: bigint;
  };
  Winner: {
    winner: string;
  };
}

export interface LotterieState {
  lastRequestId: bigint;
  goldToken: string;
  vrfSubscriptionId: bigint;
  vrfCoordinator: string;
  keyHash: string;
  callbackGasLimit: number;
  requestConfirmations: number;
  numWords: number;
}
