const log = console.log;
console.log = () => {};

import { ethers } from "ethers";
import { BlockTag } from "@ethersproject/abstract-provider";
import { RelicClient } from "@relicprotocol/client";
import { command, run, string, number, positional, restPositionals } from "cmd-ts";
import * as dotenv from "dotenv";

dotenv.config();

const NOUNS_TOKEN_ADDRESS = "0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03";

const app = command({
  name: "storage-slot-proof",
  args: {
    block: positional({ type: number, displayName: "block" }),
    slots: restPositionals({ type: string, displayName: "storage slots" }),
  },
  handler: async ({ slots, block }) => {
    const b: BlockTag = block;
    const provider = new ethers.providers.JsonRpcProvider(process.env.MAINNET_RPC_URL || "");
    const client = await RelicClient.fromProvider(provider);

    const data = await client.cachedMultiStorageSlotProver.getProofData({
      block: b,
      account: NOUNS_TOKEN_ADDRESS,
      slots: slots.map((s) => {
        return ethers.BigNumber.from(s);
      }),
    });

    log(data.proof);
  },
});

run(app, process.argv.slice(2));
