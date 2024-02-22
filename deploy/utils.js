const { Provider, Wallet } = require("zksync-web3");
const hrer = require("hardhat");
const { Deployer } = require("@matterlabs/hardhat-zksync-deploy");
const dotenv = require("dotenv");
const { formatEther } = require("ethers/lib/utils");

// import "@matterlabs/hardhat-zksync-node/dist/type-extensions";
// import "@matterlabs/hardhat-zksync-verify/dist/src/type-extensions";

// Load env file
dotenv.config();

const getProvider = () => {
  const rpcUrl = hre.network.config.url;
  if (hre.network.name !== "hardhat" && !rpcUrl)
    throw `⛔️ RPC URL wasn't found in "${hre.network.name}"! Please add a "url" field to the network config in hardhat.config.ts`;

  // Initialize zkSync Provider
  const provider = new Provider(rpcUrl);

  return provider;
};

const getWallet = (privateKey) => {
  if (!privateKey) {
    if (!process.env.PRIVATE_KEY)
      // if (!process.env.LOCAL_PRIVATE_KEY)
      throw "⛔️ Wallet private key wasn't found in .env file!";
  }

  const provider = getProvider();

  // Initialize zkSync Wallet
  const wallet = new Wallet(
    privateKey ?? process.env.PRIVATE_KEY,
    // process.env.LOCAL_PRIVATE_KEY,
    provider
  );

  return wallet;
};

const verifyEnoughBalance = async (wallet, amount) => {
  // Check if the wallet has enough balance
  const balance = await wallet.getBalance();
  if (balance.lt(amount))
    throw `⛔️ Wallet balance is too low! Required ${formatEther(
      amount
    )} ETH, but current ${wallet.address} balance is ${formatEther(
      balance
    )} ETH`;
};

/**
 * @param {string} data.contract The contract's path and name. E.g., "contracts/Greeter.sol:Greeter"
 */
const verifyContract = async (data) => {
  const verificationRequestId = await hre.run("verify:verify", {
    ...data,
    noCompile: true,
  });
  return verificationRequestId;
};

// type DeployContractOptions = {
//   /**
//    * If true, the deployment process will not print any logs
//    */
//   silent?: boolean;
//   /**
//    * If true, the contract will not be verified on Block Explorer
//    */
//   noVerify?: boolean;
//   /**
//    * If specified, the contract will be deployed using this wallet
//    */
//   wallet?: Wallet;
// };
const deployContract = async (
  contractArtifactName,
  constructorArguments,
  options
) => {
  const log = (message) => {
    if (!options?.silent) console.log(message);
  };

  log(`\nStarting deployment process of "${contractArtifactName}"...`);

  const wallet = options?.wallet ?? getWallet();
  const deployer = new Deployer(hre, wallet);

  const artifact = await deployer
    .loadArtifact(contractArtifactName)
    .catch((error) => {
      if (
        error?.message?.includes(
          `Artifact for contract "${contractArtifactName}" not found.`
        )
      ) {
        console.error(error.message);
        throw `⛔️ Please make sure you have compiled your contracts or specified the correct contract name!`;
      } else {
        throw error;
      }
    });

  // Estimate contract deployment fee
  const deploymentFee = await deployer.estimateDeployFee(
    artifact,
    constructorArguments || []
  );
  log(`Estimated deployment cost: ${formatEther(deploymentFee)} ETH`);

  // Check if the wallet has enough balance
  await verifyEnoughBalance(wallet, deploymentFee);

  // Deploy the contract to zkSync
  const contract = await deployer.deploy(artifact, constructorArguments);

  const constructorArgs = contract.interface.encodeDeploy(constructorArguments);
  const fullContractSource = `${artifact.sourceName}:${artifact.contractName}`;

  // Display contract deployment info
  log(`\n"${artifact.contractName}" was successfully deployed:`);
  log(` - Contract address: ${contract.address}`);
  log(` - Contract source: ${fullContractSource}`);
  log(` - Encoded constructor arguments: ${constructorArgs}\n`);

  if (!options?.noVerify && hre.network.config.verifyURL) {
    log(`Requesting contract verification...`);
    await verifyContract({
      address: contract.address,
      contract: fullContractSource,
      constructorArguments: constructorArgs,
      bytecode: artifact.bytecode,
    });
  }

  return contract;
};

module.exports.getProvider = getProvider;
module.exports.getWallet = getWallet;
module.exports.verifyEnoughBalance = verifyEnoughBalance;
module.exports.verifyContract = verifyContract;
module.exports.deployContract = deployContract;
