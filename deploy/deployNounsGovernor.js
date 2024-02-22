//@ts-check

const { ethers } = require("ethers");
const { deployContract, getWallet } = require("./utils.js");
const hre = require("hardhat");

const NULL = "0x0000000000000000000000000000000000000000";
const BOTSWARM = "0x035342Fb880F46A9F58343774F131Bf6f6757007";

// Mainnet
const LILNOUNS_TOKEN_BALANCE_SLOT = 4;
const LILNOUNS_DELEGATE_SLOT = 11;
const LILNOUNS_TOKEN = "0x4b10701Bfd7BFEdc47d50562b76b436fbB5BdB3B";
const NOUNS_DAO = "0x6f3E6272A167e8AcCb32072d08E0957F9c79223d";
const RELAYER = "0x675188c46d47198e9b868633b67adaa16f8f4fcb"; // Set this before deploying

// ZkSync
const RELIQUARY = "0xa3E2aF8E0b9C93E5DEE701906F228B0f56f13eC5";
const STORAGE_PROVER = "0x67652cD99C7AB61c6b2ba384fF72718C43b90970";
const LOG_PROVER = "0xf53dA51fA5Ae185Cedd01e7CC3c0bf580E4b165c";
const TRANSACTION_PROVER = "0x38DE964FeaD93231060CF1B16c2bcdb6eEA86c27";
const ZKSYNC_MESSENGER = "0x0000000000000000000000000000000000008008";

module.exports = async function () {
  const wallet = getWallet();

  const factValidator = {
    address: "0x40F3bD827F9f02b9081dBb9dCfd2Ba6f3D987c2D",
  };
  // const factValidator = await deployContract("FactValidator");
  console.log("FactValidator: ", factValidator.address);

  const nounsGovernor = new ethers.Contract(
    "0x12A8924D3B8F96c6B13eEbd022c1414d0b537Ad9",
    (await hre.artifacts.readArtifact("NounsGovernor")).abi,
    wallet
  );
  // const nounsGovernor = await deployContract("NounsGovernor", [
  //   {
  //     reliquary: RELIQUARY,
  //     nativeToken: LILNOUNS_TOKEN,
  //     externalDAO: NOUNS_DAO,
  //     storageProver: STORAGE_PROVER,
  //     logProver: LOG_PROVER,
  //     transactionProver: TRANSACTION_PROVER,
  //     factValidator: factValidator.address,
  //     messenger: ZKSYNC_MESSENGER,
  //     tokenDelegateSlot: LILNOUNS_DELEGATE_SLOT,
  //     tokenBalanceSlot: LILNOUNS_TOKEN_BALANCE_SLOT,
  //     maxProverVersion: ethers.BigNumber.from(0),
  //     castWindow: ethers.BigNumber.from(3_600), // ~12 hours
  //     finalityBlocks: ethers.BigNumber.from(7_200), // ~24 hours
  //   },
  //   {
  //     refundBaseGas: ethers.BigNumber.from(36_000),
  //     maxRefundPriorityFee: ethers.utils.parseUnits("1", "gwei"),
  //     maxRefundGasUsed: ethers.BigNumber.from(200_000),
  //     maxRefundBaseFee: ethers.utils.parseUnits("80", "gwei"),
  //     tipAmount: ethers.utils.parseUnits("0.0025", "ether"),
  //   },
  //   RELAYER, // Owner, if not the relayer, transfer to it after deployment below
  // ]);
  console.log("NounsGovernor: ", nounsGovernor.address);

  // const transferOwnership = await nounsGovernor.transferOwnership(RELAYER, {
  //   gasLimit: 1_000_000,
  // });
  // console.log("transferOwnership: ", transferOwnership);
};
