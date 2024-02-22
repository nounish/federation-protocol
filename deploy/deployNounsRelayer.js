// @ts-check
const hre = require("hardhat");
const viem = require("viem");

const NULL = "0x0000000000000000000000000000000000000000";

// Mainnet
const BASE = "0x0ceD883DEc9861B4805E59A15CFa17697c6c3c3c"; // LilNouns Base Wallet
const BASE_ADMIN = "0xB6ecAefbcaCBEaAc2Eba87EAA0ADe51a59E984e8"; // LilNouns Proxy Admin
const BASE_IMPL = "0xC1DdC447cb8B267562980F36Af05644e6c708188"; // LilNouns Base Wallet Implementation
const LILNOUNS_TOKEN = "0x4b10701Bfd7BFEdc47d50562b76b436fbB5BdB3B";
const NOUNS_DAO = "0x6f3E6272A167e8AcCb32072d08E0957F9c79223d";
const ZKSYNC = "0x32400084c286cf3e17e7b677ea9583e60a000324";

// ZkSync
const GOVERNOR = "0x12A8924D3B8F96c6B13eEbd022c1414d0b537Ad9"; // Set this before deploying

// module.exports = [
//   [
//     BASE,
//     NOUNS_DAO,
//     LILNOUNS_TOKEN,
//     ZKSYNC,
//     GOVERNOR,
//     0n, // quorumVotesBPS
//   ],
//   [
//     36_000n, // refundBaseGas
//     viem.parseGwei("1"), // maxRefundPriorityFee
//     200_000n, // maxRefundGasUsed
//     viem.parseGwei("80"), // maxRefundBaseFee
//     viem.parseEther("0.0025"), // tipAmount
//   ],
// ]

async function main() {
  const publicClient = await hre.viem.getPublicClient();

  // const nounsRelayerImplementation = await hre.viem.getContractAt(
  //     "NounsRelayer",
  //     "0xdcd0a7416a5b5ddbba133a9167ce52f48dced566"
  // );
  const nounsRelayerImplementation = await hre.viem.deployContract(
    "NounsRelayer"
  );
  console.log(
    "NounsRelayerImplementation: ",
    nounsRelayerImplementation.address
  );

  // const nounsRelayerFactory = await hre.viem.getContractAt(
  //     "NounsRelayer",
  //     "0x31eed8a034c04d386a22fee83df7957ccd037ce4"
  // );
  const nounsRelayerFactory = await hre.viem.deployContract(
    "NounsRelayerFactory",
    [nounsRelayerImplementation.address]
  );
  console.log("NounsRelayerFactory: ", nounsRelayerFactory.address);

  // const nounsRelayerArgs = [
  //   [
  //     BASE,
  //     NOUNS_DAO,
  //     LILNOUNS_TOKEN,
  //     ZKSYNC,
  //     GOVERNOR,
  //     0n, // quorumVotesBPS
  //   ],
  //   [
  //     36_000n, // refundBaseGas
  //     viem.parseGwei("1"), // maxRefundPriorityFee
  //     200_000n, // maxRefundGasUsed
  //     viem.parseGwei("80"), // maxRefundBaseFee
  //     viem.parseEther("0.0025"), // tipAmount
  //   ],
  // ];
  // const nounsRelayerAddress = await nounsRelayerFactory.simulate.clone(
  //   nounsRelayerArgs
  // );
  // const nounsRelayerTx = await nounsRelayerFactory.write.clone(
  //   nounsRelayerArgs
  // );
  // await publicClient.waitForTransactionReceipt({ hash: nounsRelayerTx });
  // console.log("NounsRelayer transaction: ", nounsRelayerTx);
  // console.log("NounsRelayer: ", nounsRelayerAddress);
  console.log("NounsRelayer: ", "0x675188c46d47198e9b868633b67adaa16f8f4fcb");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
