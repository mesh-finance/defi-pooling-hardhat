# Defi Pooling Hardhat

## How to deploy on goerli
1) update the l2 defi pooling contract address in script/deploy.js
2) npx hardhat run scripts/deploy.js --network goerli

## Verify contract on etherscan
npx hardhat verify <contract_address> <constructor_args> --network goerli


## How to run test
1) npm install
2) npx hardhat compile
3) npx hardhat test
