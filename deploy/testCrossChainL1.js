const hre = require("hardhat");
const { getProvider, getWallet } = require("./utils");
const { ethers } = require("ethers");
const { REQUIRED_L1_TO_L2_GAS_PER_PUBDATA_LIMIT } = require("zksync-web3/build/src/utils");
const L1 = "0x8d5de0b5c82be294d98e9677c9c933e94174ceee";
const L2 = "0x04d51E91c689B4cf573977d79631076609fD0d14";
const ZKSYNC = "0x1908e2bf4a88f91e4ef0dc72f02b8ea36bea2319";

async function main() {
  // const l1 = await hre.viem.deployContract("TestCrossChainMessagingL1");
  const l1 = await hre.viem.getContractAt("TestCrossChainMessagingL1", L1);
  console.log("TestCrossChainMessagingL1: ", l1.address);

  const pong = await l1.write.pong(
    [
      221191, // blockNumber
      0, // index
      6, // txNumberInBlock
      // "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000045000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002",
      // "0x0000000000000000000000000000000000000000000000000000000000000045000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002",
      ethers.utils.AbiCoder.prototype.encode(
        ["uint256", "uint256", "uint256", "uint256"],
        [69, 5, 3, 2]
      ),
      [
        '0xc08d04b5eb488bd75830b43b89398aa26f78090df33b2fec82900e03bbe3b5d4',
        '0xc3d03eebfd83049991ea3d3e358b6712e7aa2e2e63dc2d4b438987cec28ac8d0',
        '0xe3697c7f33c31a9b0f0aeb8542287d0d21e8c4cf82163d0c44c7a98aa11aa111',
        '0x199cc5812543ddceeddd0fc82807646a4899444240db2c0d2f20c3cceb5f51fa',
        '0xe4733f281f18ba3ea8775dd62d2fcd84011c8c938f16ea5790fd29a03bf8db89',
        '0x1798a1fd9c8fbb818c98cff190daa7cc10b6e5ac9716b4a2649f7c2ebcef2272',
        '0x66d7c5983afe44cf15ea8cf565b34c6c31ff0cb4dd744524f7842b942d08770d',
        '0xb04e5ee349086985f74b73971ce9dfe76bbed95c84906c5dffd96504e1e5396c',
        '0xac506ecb5465659b3a927143f6d724f91d8d9c4bdb2463aee111d9aa869874db'
      ],
      ZKSYNC,
      L2,
      5_000_000, // gas limit
      REQUIRED_L1_TO_L2_GAS_PER_PUBDATA_LIMIT, // pubdata thing
    ],
    { gas: 5_000_000, value: 5000000000000000 }
  );

  console.log("pong: ", pong);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
