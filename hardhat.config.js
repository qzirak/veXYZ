const { configDotenv } = require("dotenv");

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require('@nomiclabs/hardhat-truffle5');
require('@nomiclabs/hardhat-web3');
require("hardhat-gas-reporter");
require('hardhat-contract-sizer');
require("solidity-coverage");
require('hardhat-spdx-license-identifier');
require('hardhat-abi-exporter');
require('hardhat-storage-layout');
require('@openzeppelin/hardhat-upgrades');
const fs = require("fs");
require('hardhat-deploy');
var HardhatUserConfig = require("hardhat/types/config").HardhatUserConfig;

console.info('loading the .env config...');
configDotenv();

const OVERRIDE_RPC_URL = process.env.OVERRIDE_RPC_URL || process.env.ETH_PROVIDER_URL; // Deprecated: ETH_PROVIDER_URL
const mnemonic =
    process.env.MNEMONIC ||
    "test test test test test test test test test test test junk";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.13",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  paths: {
    sources: "./none",
    artifacts: "./out"
  },
  namedAccounts: {
    deployer: { default: 0 },
    alice: { default: 1 },
    bob: { default: 2 },
    rando: { default: 3 }
  },
  networks: {
    // This is the unchangeable default network which is started with `hardhat node`
    hardhat: {
      accounts: { mnemonic },
      allowUnlimitedContractSize: true,
      chainId: 1337,
      gas: 25e6,
      gasPrice: 20e10,
    },
    arbitrum: {
      url: OVERRIDE_RPC_URL || `https://arb1.arbitrum.io/rpc`,
      accounts: { mnemonic },
      chainId: 42161
    },
    chapel: {
      accounts: { mnemonic },
      chainId: 97,
      url: OVERRIDE_RPC_URL || "https://data-seed-prebsc-1-s1.binance.org:8545/"
    },
  }
}