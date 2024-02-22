const hre = require("hardhat");
const { deployContract, getWallet } = require("./utils");
const { ethers } = require("ethers");

const L2 = "0x04d51E91c689B4cf573977d79631076609fD0d14";
const L1_MESSENGER = "0x0000000000000000000000000000000000008008";

module.exports = async () => {
  const wallet = getWallet();

  // const l2 = await deployContract("TestCrossChainMessagingL2", [L1]);
  const l2 = new ethers.Contract(
    L2,
    (await hre.artifacts.readArtifact("TestCrossChainMessagingL2")).abi,
    wallet
  );
  console.log("TestCrossChainMessagingL2: ", l2.address);

  // https://goerli.explorer.zksync.io/tx/0xbdec3d890fef30a0699d59814997e98dfa156479ee6ab67420de8bc8eae80178#eventlog
  const ping = await l2.ping(L1_MESSENGER);
  console.log("ping: ", ping);
};
