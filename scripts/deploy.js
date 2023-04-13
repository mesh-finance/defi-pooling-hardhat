const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const DummyVault = await hre.ethers.getContractFactory("DummyVault");

  const usdc_address = "0x07865c6E87B9F70255377e024ace6630C1Eaa37F"
  const dummyVault = await DummyVault.deploy(usdc_address);


  await dummyVault.deployed();

  console.log("dummyVault deployed to:", dummyVault.address);

  const starknetCore = "0xde29d060D45901Fb19ED6C6e959EB22d8626708e"
  const stargate_usdc_bridge = "0xBA9cE9F22A3Cfa7Fcb5c31f6B2748b1e72C06204"
  // update l2 contract 
  const l2_defiPooling_address = "1252415694530708861054752841161071406018111832833215108240052383382346077538"

  const YearnV2Strategy = await hre.ethers.getContractFactory("YearnV2Strategy");
  const yearnV2Strategy = await YearnV2Strategy.deploy(usdc_address, dummyVault.address, starknetCore, l2_defiPooling_address, stargate_usdc_bridge);

  await yearnV2Strategy.deployed();

  console.log("yearnV2Strategy deployed to:", yearnV2Strategy.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
