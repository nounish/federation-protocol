//@ts-check
const hre = require("hardhat");

async function main() {
  const mockLilNounsToken = await hre.viem.deployContract("MockLilNounsToken");
  console.log("MockLilNounsToken: ", mockLilNounsToken.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
