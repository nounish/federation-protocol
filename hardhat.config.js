require("@nomicfoundation/hardhat-foundry");
require("@matterlabs/hardhat-zksync-solc");
require("@nomicfoundation/hardhat-viem");
require("@matterlabs/hardhat-zksync-deploy");
require("@matterlabs/hardhat-zksync-verify");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
      viaIR: true,
    },
  },
  zksolc: {
    version: "1.3.16",
  },
  defaultNetwork: "zkSyncMainnet",
  etherscan: {
    apiKey: process.env.ETHERSCAN_KEY,
  },
  networks: {
    mainnet: {
      url: process.env.MAINNET_RPC_URL,
      zksync: false,
      accounts: [process.env.PRIVATE_KEY],
    },
    goerli: {
      url: process.env.GOERLI_RPC_URL,
      zksync: false,
      accounts: [process.env.PRIVATE_KEY],
    },
    zkSyncMainnet: {
      url: "https://mainnet.era.zksync.io",
      ethNetwork: "mainnet",
      zksync: true,
      accounts: [process.env.PRIVATE_KEY],
      verifyURL:
        "https://zksync2-mainnet-explorer.zksync.io/contract_verification",
    },
    zkSyncTestnet: {
      url: "https://sepolia.era.zksync.dev",
      ethNetwork: "sepolia",
      zksync: true,
      accounts: [process.env.PRIVATE_KEY],
      verifyURL:
        "https://explorer.sepolia.era.zksync.dev/contract_verification",
    },
    zkSyncTestnetGoerli: {
      url: "https://zksync2-testnet.zksync.dev",
      // url: "http://localhost:8011",
      ethNetwork: "goerli",
      accounts: [
        process.env.PRIVATE_KEY,
        // process.env.LOCAL_PRIVATE_KEY,
      ],
      zksync: true,
      verifyURL:
        "https://zksync2-testnet-explorer.zksync.dev/contract_verification",
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      zksync: false,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};
