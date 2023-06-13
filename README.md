# Federation Protocol

[![Built by wiz][builtby-badge]][wiz]
[![License][license-badge]][license]
<!-- ![build status](https://github.com/nounish/federation-protocol/actions/workflows/test.yml/badge.svg) -->

<p align="center">
<img src="https://i.postimg.cc/bwWDw2n2/1684202030294.jpg" width="420" />
</p>

<p align="center" width="672">
<a href="https://federation.wtf">Federation</a> is a protocol and collection of modules for coordinating around shared governance rights onchain
</p>

---

## Modules

The protocol is open and designed to be extended with new functionality through modules.


### Nouns governance pools

Nouns holders can delegate their Noun(s) to a governance pool. The collective voting power of the pool is then auctioned off to the highest bidder. Those who delegate to a governance pool earn rewards from each auction in proportion to the amount of votes they own / total pool size. This is possible through the use of ZKProofs and as a result no asset staking or registration is required to join a pool.

Auctions for governance pools end at a fixed time so that votes are always cast before a voting period ends. If a vote could not be cast in time, the highest bidder can claim a full refund. If a vote is cast but the proposal is then canceled or vetoed, the highest bidder can claim a partial refund (minus any configured fees + gas refunds + tips).

### Scalable cross governance (dao->dao)

Coming soon

## Audit

This code has not been formally audited. However it has been reviewed by the team at [Relic protocol](https://relicprotocol.com/) to ensure that proof verification is done in a secure way. It's also heavily tested, but keep in mind that contract risk exists.

## Build and run tests

Ensure you have the following dependencies installed:
- [node](https://nodejs.org/en)
- [yarn](https://www.npmjs.com/package/yarn) 
- [foundry](https://book.getfoundry.sh/getting-started/installation)

In the root directory run:
    
    make

[wiz]: https://twitter.com/0xWiz_
[license]: https://github.com/nounish/federation-protocol/blob/master/LICENSE
[builtby-badge]: https://img.shields.io/badge/built%20by-wiz%20%E2%8C%90%E2%97%A8--%E2%97%A8-%236758ee
[license-badge]: https://img.shields.io/badge/license-GPL%203.0-orange