const hre = require('hardhat')

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main () {
  const ethers = hre.ethers

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  let plutusTokenAddress = "0xA2a42fB5E742f441414f73fF1E875d53A79C4ed7";
  let nftTokenAddress = "";

  const PlutusNFT = await ethers.getContractFactory('PlutusNFT', {
    signer: (await ethers.getSigners())[0]
  })

  const nftContract = await PlutusNFT.deploy();
  await nftContract.deployed()

  console.log('Plutus NFT token deployed to:', nftContract.address)
  nftTokenAddress = nftContract.address;
  
  await sleep(60);
  await hre.run("verify:verify", {
    address: nftContract.address,
    contract: "contracts/PlutusNFT.sol:PlutusNFT",
    constructorArguments: [],
  })

  console.log('Plutus NFT contract verified')


  const PlutusSwap = await ethers.getContractFactory('PlutusNFTSwap', {
    signer: (await ethers.getSigners())[0]
  })

  const swapContract = await PlutusSwap.deploy(plutusTokenAddress, nftTokenAddress, '0xc2A79DdAF7e95C141C20aa1B10F3411540562FF7');
  await swapContract.deployed()

  console.log('Plutus NFT Swap deployed to:', swapContract.address)
  
  await sleep(60);
  await hre.run("verify:verify", {
    address: swapContract.address,
    contract: "contracts/PlutusNFTSwap.sol:PlutusNFTSwap",
    constructorArguments: [plutusTokenAddress, nftTokenAddress, '0xc2A79DdAF7e95C141C20aa1B10F3411540562FF7'],
  })

  console.log('Plutus Swap Contract verified')
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
