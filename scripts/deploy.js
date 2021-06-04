const hre = require('hardhat')

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main () {
  const ethers = hre.ethers
  const upgrades = hre.upgrades;

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  let plutusTokenAddress = "0x1C20d2b2F46916DDA8c4fAea6aeE15b4437f39eC";
  let nftTokenAddress = "0xa0E386b51c4d7788190aEd09397929560a1845C5";
  let plutusSwapAddress = "0xE8Da7037f5F59C2806A24b61f931b6a865dA3179";
  let deployFlag = {
    deployAluturaFaucet: false,
    deployAlturaToken: false,
    deployAlturaSwap: false,
    upgradeAlturaSwap: true,
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
    const PlutusSwap = await ethers.getContractFactory('AlturaNFTSwap', {
      signer: (await ethers.getSigners())[0]
    })
  
    const swapContract = await upgrades.deployProxy(PlutusSwap, 
      [plutusTokenAddress, '0xc2A79DdAF7e95C141C20aa1B10F3411540562FF7'],
      {initializer: 'initialize',kind: 'uups'});
    await swapContract.deployed()
  
    console.log('Altura NFT Swap deployed to:', swapContract.address)
    plutusSwapAddress = swapContract.address;
  } 

  /**
   *  Upgrade AlturaNFT Swap
   */
  if(deployFlag.upgradeAlturaSwap) {
    const PlutusSwapV2 = await ethers.getContractFactory('AlturaNFTSwap', {
      signer: (await ethers.getSigners())[0]
    })
  
    await upgrades.upgradeProxy(plutusSwapAddress, PlutusSwapV2);

    console.log('Altura NFT Swap V2 upgraded')
    
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
