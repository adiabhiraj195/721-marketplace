const { ethers, network } = require("hardhat");
// const { moveBlocks } = require("../utils/move-blocks");

const PRICE = ethers.parseEther("0.1");
console.log(PRICE);
// const PRICE = ethers.utils.parseEther("0.1");

async function mintAndList() {
  console.log("hii");
  const nftMarketplace = await ethers.getContractAt(
    "NftMarketplace",
    "0x407a6Ef8Bef858Ea32B0b27F6d7faC237fd83c4e"
  );
  console.log(nftMarketplace);

  const tokenId = 0;

  console.log("Listing NFT...");
  const tx = await nftMarketplace.listItem(
    "0x3FBf1bf55cD660A06019923Ef8dD58E3ba5B0791",
    tokenId,
    PRICE
  );
  await tx.wait(1);
  console.log("NFT Listed!");
  //   if (network.config.chainId == 31337) {
  //     // Moralis has a hard time if you move more than 1 at once!
  //     await moveBlocks(1, (sleepAmount = 1000));
  //   }
}

mintAndList()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
