const hre = require('hardhat')

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main () {
  const ethers = hre.ethers
  const upgrades = hre.upgrades;

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  let plutusTokenAddress = "0x663b92A7eac229A7EE8290B10dC17463bFf206a7";
  let nftTokenAddress = "0xd65F17975845340B1D6b049cfA698578E62B289d";
  let plutusSwapAddress = "";
  let deployFlag = {
    deployAlturaToken: false,
    deployAlturaSwap: true,
    upgradeAlturaSwap: false,
  };

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
  
    const swapContract = await upgrades.deployProxy(PlutusSwap, [plutusTokenAddress, nftTokenAddress, '0xc2A79DdAF7e95C141C20aa1B10F3411540562FF7']);
    await swapContract.deployed()
  
    console.log('Altura NFT Swap deployed to:', swapContract.address)
    plutusSwapAddress = swapContract.address;
    
    await sleep(60);
    await hre.run("verify:verify", {
      address: swapContract.address,
      contract: "contracts/AlturaNFTSwap.sol:AlturaNFTSwap",
      constructorArguments: [plutusTokenAddress, nftTokenAddress, '0xc2A79DdAF7e95C141C20aa1B10F3411540562FF7'],
    })
  
    console.log('Altura Swap Contract verified')
  } 

  /**
   *  Upgrade AlturaNFT Swap
   */
  if(deployFlag.upgradeAlturaSwap) {
    const PlutusSwapV2 = await ethers.getContractFactory('AlturaNFTSwapV2', {
      signer: (await ethers.getSigners())[0]
    })
  
    const swapContractV2 = await upgrades.upgradeProxy(plutusSwapAddress, PlutusSwapV2);

    console.log('Altura NFT Swap V2 upgraded to:', swapContractV2)
    
    // await sleep(60);
    // await hre.run("verify:verify", {
    //   address: swapContractV2.address,
    //   contract: "contracts/AlturaNFTSwap.sol:AlturaNFTSwap",
    //   constructorArguments: [plutusTokenAddress, nftTokenAddress, '0xc2A79DdAF7e95C141C20aa1B10F3411540562FF7'],
    // })
  
    console.log('Altura Swap Contract V2 verified')
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
