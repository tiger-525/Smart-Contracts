const hre = require('hardhat')

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main () {
  const ethers = hre.ethers
  const upgrades = hre.upgrades;

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  let plutusTokenAddress = "0x8263CD1601FE73C066bf49cc09841f35348e3be0";
  let nftTokenAddress = "0xa0E386b51c4d7788190aEd09397929560a1845C5";
  let plutusSwapAddress = "0xe29F0B490F0d89CA7ACAc1C7BeD2E07eCAD65201";
  let plutusLootboxAddress = "0x6AAd1ad63D94e4d1455A4D6e1aE9ee50C85374cb";

  let deployFlag = {
    deployAluturaFaucet: false,
    deployAlturaToken: false,
    deployAlturaSwap: false,
    upgradeAlturaSwap: false,
    deployAlturaLootbox: true,
    upgradeAlturaLootbox: false,
  };


  /**
   *  Deploy Altura Faucet
   */
   if(deployFlag.deployAluturaFaucet) {
    const AlturaFaucet = await ethers.getContractFactory('AlturaFaucet', {
      signer: (await ethers.getSigners())[0]
    })
  
    const faucetContract = await AlturaFaucet.deploy(plutusTokenAddress);
    await faucetContract.deployed()
  
    console.log('Altura Faucet deployed to:', faucetContract.address)
    
    await sleep(60);
    await hre.run("verify:verify", {
      address: faucetContract.address,
      contract: "contracts/AlturaFaucet.sol:AlturaFaucet",
      constructorArguments: [plutusTokenAddress],
    })
  
    console.log('Altura Faucet contract verified')
  }

  /**
   *  Deploy Altura NFT Token
   */
  if(deployFlag.deployAlturaToken) {
    const AlturaNFT = await ethers.getContractFactory('AlturaNFT', {
      signer: (await ethers.getSigners())[0]
    })
  
    const nftContract = await AlturaNFT.deploy('AlturaNFT', 'https://plutus-app-mvp.herokuapp.com/api/item/');
    await nftContract.deployed()
  
    console.log('Altura NFT token deployed to:', nftContract.address)
    nftTokenAddress = nftContract.address;
    
    await sleep(60);
    await hre.run("verify:verify", {
      address: nftContract.address,
      contract: "contracts/AlturaNFT.sol:AlturaNFT",
      constructorArguments: ['AlturaNFT', 'https://plutus-app-mvp.herokuapp.com/api/item/'],
    })
  
    console.log('Altura NFT contract verified')
  }
  
  /**
   *  Deploy AlturaNFT Swap
   */
  if(deployFlag.deployAlturaSwap) {
    const PlutusSwap = await ethers.getContractFactory('AlturaNFTFactory', {
      signer: (await ethers.getSigners())[0]
    })
  
    const swapContract = await upgrades.deployProxy(PlutusSwap, 
      ['0xAeAF8FcC925d254fC62051a12fF13da1aFfa5Ed4'],
      {initializer: 'initialize',kind: 'uups'});
    await swapContract.deployed()
  
    console.log('Altura NFT Swap deployed to:', swapContract.address)
    plutusSwapAddress = swapContract.address;
  } 

  /**
   *  Upgrade AlturaNFT Swap
   */
  if(deployFlag.upgradeAlturaSwap) {
    const PlutusSwapV2 = await ethers.getContractFactory('AlturaNFTFactory', {
      signer: (await ethers.getSigners())[0]
    })
  
    await upgrades.upgradeProxy(plutusSwapAddress, PlutusSwapV2);

    console.log('Altura NFT Swap V2 upgraded')
    
  }



  /**
   *  Deploy Altura Lootbox factory
   */
   if(deployFlag.deployAlturaLootbox) {
    const PlutusLootbox = await ethers.getContractFactory('AlturaLootboxFactory', {
      signer: (await ethers.getSigners())[0]
    })
  
    const lootboxContract = await upgrades.deployProxy(PlutusLootbox, 
      ['0xAeAF8FcC925d254fC62051a12fF13da1aFfa5Ed4'],
      {initializer: 'initialize',kind: 'uups'});
    await lootboxContract.deployed()
  
    console.log('Altura  Lootbox deployed to:', lootboxContract.address)
  } 

  /**
   *  Upgrade Altura Lootbox factory
   */
  if(deployFlag.upgradeAlturaLootbox) {
    const PlutusLootboxV2 = await ethers.getContractFactory('AlturaLootboxFactory', {
      signer: (await ethers.getSigners())[0]
    })
  
    await upgrades.upgradeProxy(plutusLootboxAddress, PlutusLootboxV2);

    console.log('Altura Lootbox factory V2 upgraded')
    
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
