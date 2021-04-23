require('dotenv').config()
require('@nomiclabs/hardhat-ethers')
require("@nomiclabs/hardhat-etherscan");


module.exports = {
  networks: {
    testnet: {
      url: process.env.NODE_URL,
      accounts: [process.env.PRIVATE_KEY]
    }
  },
  solidity: {
    compilers: [
      {
        version: '0.7.2',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
    ]
  },
  etherscan: {
    apiKey: "Y5HQ4K5GQ7Y4UPVJW4ZGWEZ59BIV4XWTFU"
  }
}
