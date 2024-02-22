//@ts-check

const { Provider, utils } = require("zksync-web3");
const { getProvider, getWallet } = require("./utils");
const { ethers } = require("ethers");
require("dotenv").config();

const l2ContractAddress = "0x04d51E91c689B4cf573977d79631076609fD0d14";
const l2TransactionHash =
  "0xbdec3d890fef30a0699d59814997e98dfa156479ee6ab67420de8bc8eae80178";

async function main() {
  const l1Provider = new ethers.providers.StaticJsonRpcProvider(
    process.env.GOERLI_RPC_URL
  );
  const zkSyncProvider = await getProvider();

  const message = ethers.utils.AbiCoder.prototype.encode(
    ["uint256", "uint256", "uint256", "uint256"],
    [69, 5, 3, 2]
  );
  console.log("message", message);

  // const message =
  //   "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000045000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002";
  const messageHash = ethers.utils.keccak256(message);
  // Actual hash: "0x33ff89b6c9cbbfff9b4c4f9fb6b26365ce4b2ffc71f983524625c52f0615ac17"
  console.log("hash", messageHash);

  console.log("Waiting for L1 block inclusion (this may take up to 1 hour)...");

  const { l1BatchNumber, l1BatchTxIndex, blockNumber } =
    await zkSyncProvider.getTransactionReceipt(l2TransactionHash);
  if (l1BatchNumber) {
    const zkAddress = await zkSyncProvider.getMainContractAddress();

    const sender = l2ContractAddress;
    const proofInfo = await zkSyncProvider.getMessageProof(
      blockNumber,
      sender,
      messageHash
    );
    if (!proofInfo) {
      throw new Error("No proof found");
    }
    const index = proofInfo.id;
    const proof = proofInfo.proof;

    const mailboxL1Contract = new ethers.Contract(
      zkAddress,
      utils.ZKSYNC_MAIN_ABI,
      l1Provider
    );

    // all the information of the message sent from L2
    const messageInfo = {
      txNumberInBlock: l1BatchTxIndex,
      sender,
      data: message,
    };

    try {
      const result = await mailboxL1Contract.proveL2MessageInclusion(
        l1BatchNumber,
        index,
        messageInfo,
        proof
      );
      console.log("L2 block:", blockNumber);
      console.log("L1 Index for Tx in block:", l1BatchTxIndex);
      console.log("L1 Batch for block: ", l1BatchNumber);
      console.log("Inclusion proof:", proof);
      console.log("proveL2MessageInclusion:", result);
    } catch (err) {
      console.error(err);
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
