const log = console.log;
console.log = () => {};

import { ethers } from "ethers";
import { BlockTag } from "@ethersproject/abstract-provider";
import { RelicClient } from "@relicprotocol/client";
import { command, run, string, number, positional } from "cmd-ts";
import * as dotenv from "dotenv";

dotenv.config();

const app = command({
  name: "account-proof",
  args: {
    account: positional({ type: string, displayName: "address" }),
    block: positional({ type: number, displayName: "block" }),
  },
  handler: async ({ account, block }) => {
    const b: BlockTag = block;
    const provider = new ethers.providers.JsonRpcProvider(process.env.MAINNET_RPC_URL || "");
    const client = await RelicClient.fromProvider(provider);

    const data = await client.accountStorageProver.getProofData({ block: b, account });
    log(data.proof);
  },
});

run(app, process.argv.slice(2));
