/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 import { task } from "hardhat/config";
 import "@nomiclabs/hardhat-waffle";
 import 'dotenv/config';
 import "@nomiclabs/hardhat-etherscan";
 export default  {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      // If you want to do some forking set `enabled` to true
      forking: {
        url: process.env.MAINNET_RPC_URL,
        blockNumber: 14758829,
        enabled: false,
      },
      chainId: 31337,
    },
    goerli: {
      url: process.env.GOERLI_RPC_URL,
      accounts : [process.env.PRIVATE_KEY]
   },
    localhost: {
      chainId: 31337,
    },
  },
  etherscan : {
    apiKey: process.env.ETHERSCAN_API_KEY
  },
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          metadata: {
            // Not including the metadata hash
            // https://github.com/paulrberg/solidity-template/issues/31
            bytecodeHash: "none",
          },
          // Disable the optimizer when debugging
          // https://hardhat.org/hardhat-network/#solidity-optimizer-support
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.7.4",
        settings: {
          metadata: {
            // Not including the metadata hash
            // https://github.com/paulrberg/solidity-template/issues/31
            bytecodeHash: "none",
          },
          // Disable the optimizer when debugging
          // https://hardhat.org/hardhat-network/#solidity-optimizer-support
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          metadata: {
            // Not including the metadata hash
            // https://github.com/paulrberg/solidity-template/issues/31
            bytecodeHash: "none",
          },
          // Disable the optimizer when debugging
          // https://hardhat.org/hardhat-network/#solidity-optimizer-support
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
};
