export enum PayFeesIn {
  Native = 0,
  LINK = 1,
}

export interface TokenBridgeState {
  destinationChainSelector: bigint;
  goldToken: string;
  link: string;
  goldTokenBalance: bigint;
  linkBalance: bigint;
  isPaused: boolean;
}

export interface BridgeTokensParams {
  receiver: string;
  amount: bigint;
  payFeesIn: PayFeesIn;
}

export interface SetWhitelistedChainParams {
  chainSelector: bigint;
  enabled: boolean;
  ccipExtraArgs: string;
}

export interface SetWhitelistedSenderParams {
  sender: string;
  enabled: boolean;
}

export interface WithdrawParams {
  beneficiary: string;
}

export interface WithdrawTokenParams {
  beneficiary: string;
  token: string;
}

// Events
export interface TokensBridgedEvent {
  messageId: string;
  sender: string;
  receiver: string;
  amount: bigint;
  destinationChainSelector: bigint;
  feeToken: string;
  fees: bigint;
}

export interface TokensReceivedEvent {
  messageId: string;
  receiver: string;
  amount: bigint;
  sourceChainSelector: bigint;
}

export interface ChainWhitelistedEvent {
  chainSelector: bigint;
}

export interface ChainRemovedEvent {
  chainSelector: bigint;
}

export interface SenderWhitelistedEvent {
  sender: string;
}

export interface SenderRemovedEvent {
  sender: string;
}

export interface TokenBridgeInitializedEvent {
  owner: string;
  link: string;
  goldToken: string;
  destinationChainSelector: bigint;
}

export interface MessageProcessedWithoutTokenEvent {
  messageId: string;
  sourceChainSelector: bigint;
}
