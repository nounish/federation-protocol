//@ts-check
const hre = require("hardhat");
const viem = require("viem");
const {
  RelicClient,
  MultiStorageSlotProver,
  LogProver,
  TransactionProver,
  utils,
} = require("@relicprotocol/client");
const { ethers } = require("ethers");

const NULL = "0x0000000000000000000000000000000000000000";

// const NOUNS_TOKEN_BALANCE_SLOT = 4;
// const NOUNS_DELEGATE_SLOT = 11;

const MOCK_LILNOUNS_TOKEN_BALANCE_SLOT = 3;
const MOCK_LILNOUNS_DELEGATE_SLOT = 10;

// Sepolia Testnet
const SEPOLIA_NOUNS_DAO = "0x35d2670d7C8931AACdd37C89Ddcb0638c3c44A57";
const SEPOLIA_BASE_WALLET = "0x431a7af2752Cb62D522854F752a61C3778Ef7462";
const SEPOLIA_MOCK_LILNOUNS_TOKEN =
  "0x05A21D6e346594eFc88eF898cE64Ef4C6080074D";

const SEPOLIA_RELIQUARY = "0x64357cc3387ff4aae07b69f2f0a71201532401b4";
const SEPOLIA_STORAGE_PROVER = "0x218E4F876EceF0Bd8557075E31888F4560c43A55";
const SEPOLIA_LOG_PROVER = "0xC97069E6934B5f2c032401d33756be3163eFF259";
const SEPOLIA_TRANSACTION_PROVER = "0xc4842B450681EC48DEc69ec4d5010062CEB69142";

const REFUND_BASE_GAS = 36000;
const MAX_REFUND_PRIORITY_FEE = viem.parseGwei("1");
const MAX_REFUND_GAS_USED = 200_000;

// Format message
// Relay proposal

// For use of verifying contracts (constructor args)
// module.exports = [
//   [
//     "0x035342Fb880F46A9F58343774F131Bf6f6757007", // base wallet (omitted for testing)
//     SEPOLIA_NOUNS_DAO,
//     SEPOLIA_MOCK_LILNOUNS_TOKEN,
//     NULL, // zkSync (omitted for testing)
//     "0x1015f46175bb28985807c4602e84ccf17c9a2f75", // governor
//     0n, // quorumVotesBPS
//   ],
//   [
//     REFUND_BASE_GAS, // refundBaseGas
//     MAX_REFUND_PRIORITY_FEE, // maxRefundPriorityFee
//     MAX_REFUND_GAS_USED, // maxRefundGasUsed
//     0n, // maxRefund
//     viem.parseGwei("80"), // maxRefundBaseFee
//     viem.parseEther("0.0025"), // tipAmount
//   ],
// ];

async function testnet() {
  //////////////////////////////////////////////////////////////
  ///////////////////// DEPLOY & CONFIG ////////////////////////
  //////////////////////////////////////////////////////////////

  const publicClient = await hre.viem.getPublicClient();
  const walletClient = await hre.viem.getWalletClient(
    "0x035342Fb880F46A9F58343774F131Bf6f6757007"
  );

  const base = await hre.viem.getContractAt("Base", SEPOLIA_BASE_WALLET);
  console.log("Base: ", base.address);

  const factValidator = await hre.viem.getContractAt(
    "FactValidator",
    "0x58489d01c78000749fab5157b3d6f0a2dc5c5b93"
  );
  // const factValidator = await hre.viem.deployContract("FactValidator");
  console.log("FactValidator: ", factValidator.address);

  const mockNounsGovernor = await hre.viem.getContractAt(
    "MockNounsGovernor",
    "0x1015f46175bb28985807c4602e84ccf17c9a2f75"
  );
  // const mockNounsGovernor = await hre.viem.deployContract("MockNounsGovernor", [
  //   [
  //     SEPOLIA_RELIQUARY,
  //     SEPOLIA_MOCK_LILNOUNS_TOKEN,
  //     SEPOLIA_NOUNS_DAO,
  //     SEPOLIA_STORAGE_PROVER,
  //     SEPOLIA_LOG_PROVER,
  //     SEPOLIA_TRANSACTION_PROVER,
  //     factValidator.address,
  //     NULL, // messenger (omitted for testing)
  //     MOCK_LILNOUNS_DELEGATE_SLOT,
  //     MOCK_LILNOUNS_TOKEN_BALANCE_SLOT,
  //     0n, // maxProverVersion
  //     25n, // castWindow
  //     0n, // finalityBlocks
  //   ],
  //   [
  //     REFUND_BASE_GAS, // refundBaseGas
  //     MAX_REFUND_PRIORITY_FEE, // maxRefundPriorityFee
  //     MAX_REFUND_GAS_USED, // maxRefundGasUsed
  //     viem.parseGwei("80"), // maxRefundBaseFee
  //     viem.parseEther("0.0025"), // tipAmount
  //   ],
  //   "0x035342Fb880F46A9F58343774F131Bf6f6757007", // Relayer (omitted for testing)
  // ]);
  console.log("MockNounsGovernor: ", mockNounsGovernor.address);

  const mockNounsRelayerImplementation = await hre.viem.getContractAt(
    "MockNounsRelayer",
    "0xfaa57904b2c87e1b0d71791321d725e8764c1335"
  );
  // const mockNounsRelayerImplementation = await hre.viem.deployContract(
  //   "MockNounsRelayer"
  // );
  console.log(
    "MockNounsRelayerImplementation: ",
    mockNounsRelayerImplementation.address
  );

  const nounsRelayerFactory = await hre.viem.getContractAt(
    "MockNounsRelayer",
    "0x9999a2663b072b732e5d7ebdd536c9187e954823"
  );
  // const nounsRelayerFactory = await hre.viem.deployContract(
  //   "NounsRelayerFactory",
  //   [mockNounsRelayerImplementation.address]
  // );
  console.log("NounsRelayerFactory: ", nounsRelayerFactory.address);

  // const mockNounsRelayerArgs = [
  //   [
  //     "0x035342Fb880F46A9F58343774F131Bf6f6757007", // base wallet (omitted for testing)
  //     SEPOLIA_NOUNS_DAO,
  //     SEPOLIA_MOCK_LILNOUNS_TOKEN,
  //     NULL, // zkSync (omitted for testing)
  //     mockNounsGovernor.address, // governor
  //     0n, // quorumVotesBPS
  //   ],
  //   [
  //     REFUND_BASE_GAS, // refundBaseGas
  //     MAX_REFUND_PRIORITY_FEE, // maxRefundPriorityFee
  //     MAX_REFUND_GAS_USED, // maxRefundGasUsed
  //     0n, // maxRefund
  //     viem.parseGwei("80"), // maxRefundBaseFee
  //     viem.parseEther("0.0025"), // tipAmount
  //   ],
  // ];
  // const mockNounsRelayerAddress = await nounsRelayerFactory.simulate.clone(
  //   mockNounsRelayerArgs
  // );
  // const mockNounsRelayerTx = await nounsRelayerFactory.write.clone(
  //   mockNounsRelayerArgs
  // );
  // await publicClient.waitForTransactionReceipt({ hash: mockNounsRelayerTx });
  // console.log("MockNounsRelayer transaction: ", mockNounsRelayerTx);

  const mockNounsRelayer = await hre.viem.getContractAt(
    "MockNounsRelayer",
    "0x20be2D3e6BBAB294eDBcbE9daD37D45c260d29eF"
    // @ts-ignore
    // mockNounsRelayerAddress
  );
  console.log("MockNounsRelayer: ", mockNounsRelayer.address);

  //////////////////////////////////////////////////////////////
  ///////////////////// CREATE PROPOSAL ////////////////////////
  //////////////////////////////////////////////////////////////
  const nounsDAO = viem.getContract({
    address: SEPOLIA_NOUNS_DAO,
    abi: [
      {
        inputs: [
          {
            internalType: "address[]",
            name: "targets",
            type: "address[]",
          },
          {
            internalType: "uint256[]",
            name: "values",
            type: "uint256[]",
          },
          {
            internalType: "string[]",
            name: "signatures",
            type: "string[]",
          },
          {
            internalType: "bytes[]",
            name: "calldatas",
            type: "bytes[]",
          },
          {
            internalType: "string",
            name: "description",
            type: "string",
          },
        ],
        name: "propose",
        outputs: [
          {
            internalType: "uint256",
            name: "",
            type: "uint256",
          },
        ],
        stateMutability: "nonpayable",
        type: "function",
      },
      {
        inputs: [],
        name: "proposalCount",
        outputs: [
          {
            internalType: "uint256",
            name: "",
            type: "uint256",
          },
        ],
        stateMutability: "view",
        type: "function",
      },
    ],
    publicClient,
    walletClient,
  });
  console.log("NounsDAO: ", nounsDAO.address);

  const proposalArgs = [
    [SEPOLIA_MOCK_LILNOUNS_TOKEN],
    [5n],
    [""],
    ["0x"],
    "test",
  ];

  // const proposalTx = "";
  const proposalTx = await nounsDAO.write.propose(
    //@ts-ignore
    proposalArgs,
    {
      gas: 5_000_000n,
    }
  );

  await publicClient.waitForTransactionReceipt({
    hash: proposalTx,
  });
  console.log("Proposal transaction: ", proposalTx);

  //////////////////////////////////////////////////////////////
  ///////////////////// GENERATE PROOFS ////////////////////////
  //////////////////////////////////////////////////////////////

  throw new Error("STOP");

  const ethersProvider = new ethers.providers.JsonRpcProvider(
    process.env.SEPOLIA_RPC_URL
  );

  const relic = await RelicClient.fromProvider(ethersProvider);

  const proposalReceipt = await ethersProvider.getTransactionReceipt(
    proposalTx
  );

  const proposalCreatedInterface = new ethers.utils.Interface([
    "event ProposalCreated (uint256 id, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 startBlock, uint256 endBlock, string description)",
  ]);

  let startBlock;
  let endblock;
  let proposalId;

  const proposalCreatedLog = proposalReceipt.logs.find((log) => {
    const parsedLog = proposalCreatedInterface.parseLog(log);

    if (parsedLog.name === "ProposalCreated") {
      console.log("Proposal created log: ", parsedLog.args);
      startBlock = Number(parsedLog.args.startBlock);
      proposalId = Number(parsedLog.args.id);
      endblock = Number(parsedLog.args.endBlock);
      return log;
    }
  });

  if (!proposalCreatedLog) throw new Error("Proposal log not found");

  console.log("Start block: ", startBlock);
  console.log("Proposal ID: ", proposalId);

  console.log("Waiting for start block...");
  // await new Promise((resolve) => {
  //   let done = false;
  //   publicClient.watchBlockNumber({
  //     onBlockNumber: async (blockNumber) => {
  //       console.log(BigInt(startBlock) - blockNumber, " blocks remaining");
  //       if (!done && blockNumber > startBlock + 1) {
  //         done = true;
  //         console.log("Proposal started!!!");
  //         resolve(true);
  //       }
  //     },
  //   });
  // });

  const proposalProofData = await relic.logProver.getProofData(
    proposalCreatedLog
  );
  // console.log("Proposal proof: ", proposalProofData.proof);

  const tokenBalanceSlot = utils.mapElemSlot(
    MOCK_LILNOUNS_TOKEN_BALANCE_SLOT,
    // BotSwarm
    "0x035342Fb880F46A9F58343774F131Bf6f6757007"
  );
  console.log("Token balance slot: ", tokenBalanceSlot);

  const tokenDelegateSlot = utils.mapElemSlot(
    MOCK_LILNOUNS_DELEGATE_SLOT,
    // BotSwarm
    "0x035342Fb880F46A9F58343774F131Bf6f6757007"
  );
  console.log("Token delegate slot: ", tokenDelegateSlot);

  const tokenBalanceSlot2 = utils.mapElemSlot(
    MOCK_LILNOUNS_TOKEN_BALANCE_SLOT,
    // Other account
    "0xfC4dBeddB491F81fb3E8f88Ca14b1dBA0b9717A8"
  );
  console.log("Token balance slot 2: ", tokenBalanceSlot2);

  const tokenDelegateSlot2 = utils.mapElemSlot(
    MOCK_LILNOUNS_DELEGATE_SLOT,
    // Other account
    "0xfC4dBeddB491F81fb3E8f88Ca14b1dBA0b9717A8"
  );
  console.log("Token delegate slot 2: ", tokenDelegateSlot2);

  const voterProofData = await relic.multiStorageSlotProver.getProofData({
    // @ts-ignore
    block: startBlock,
    account: SEPOLIA_MOCK_LILNOUNS_TOKEN,
    slots: [
      tokenBalanceSlot,
      tokenDelegateSlot,
      tokenBalanceSlot2,
      tokenDelegateSlot2,
    ],
  });
  // console.log("Voter proof: ", voterProofData.proof);

  //////////////////////////////////////////////////////////////
  ///////////////////// VOTE ON GOVERNOR ///////////////////////
  //////////////////////////////////////////////////////////////

  const storageProverFee = await relic.multiStorageSlotProver.fee();
  console.log("Storage prover fee: ", storageProverFee.toNumber());
  const logProverFee = await relic.logProver.fee();
  console.log("Log prover fee: ", logProverFee.toNumber());

  // const voteTx =
  //   "";
  const voteTx = await mockNounsGovernor.write.vote(
    [
      proposalId,
      1n,
      "reason",
      "metadata",
      voterProofData.proof,
      [
        // BotSwarm & Other account
        "0x035342Fb880F46A9F58343774F131Bf6f6757007",
        "0xfC4dBeddB491F81fb3E8f88Ca14b1dBA0b9717A8",
      ],
      proposalProofData.proof,
    ],
    {
      value: storageProverFee.add(logProverFee).toNumber(),
      gas: 5_000_000n,
    }
  );
  console.log("Vote transaction: ", voteTx);

  await publicClient.waitForTransactionReceipt({
    hash: voteTx,
  });

  //////////////////////////////////////////////////////////////
  /////////////////////// SETTLE VOTES /////////////////////////
  //////////////////////////////////////////////////////////////

  // const voteReceipt = await ethersProvider.getTransactionReceipt(voteTx);

  // const blockProofData = await relic.transactionProver.getProofData(
  //   voteReceipt
  // );
  // // console.log("Block proof: ", blockProofData.proof);

  // const transactionProverFee = await relic.transactionProver.fee();

  // const settleVotesArgs = [proposalId, blockProofData.proof];

  // const settleVotesMessage = await mockNounsGovernor.simulate.settleVotes(
  //   settleVotesArgs
  // );
  // console.log("Settle votes message: ", settleVotesMessage.result);

  // const settleVotesTx = await mockNounsGovernor.write.settleVotes(
  //   settleVotesArgs,
  //   { value: transactionProverFee.toNumber(), gas: 5_000_000n }
  // );
  // console.log("Settle votes transaction: ", settleVotesTx);

  //////////////////////////////////////////////////////////////
  /////////////////////// RELAY VOTES //////////////////////////
  //////////////////////////////////////////////////////////////

  // THIS MUST BE DONE BY BASE WALLET EXECUTE
  // const relayVotesTx = await mockNounsRelayer.write.relayVotes(
  //   [
  //     [
  //       // @ts-ignore
  //       settleVotesMessage.result.proposal,
  //       // @ts-ignore
  //       settleVotesMessage.result.forVotes,
  //       // @ts-ignore
  //       settleVotesMessage.result.againstVotes,
  //       // @ts-ignore
  //       settleVotesMessage.result.abstainVotes,
  //     ],
  //   ],
  //   { gas: 5_000_000n }
  // );
  // console.log("Relay votes transaction: ", relayVotesTx);
}

testnet()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
