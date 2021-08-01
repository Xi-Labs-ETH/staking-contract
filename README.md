## Token Staking Contract

This is a simple contract for rewarding token stakers with more tokens.

It's based on a fixed emissions schedule which can be set by the owner. And it is based on distributing rewards loaded into the contract, not on minting more tokens.

Sample use cases:

- Reward liquidity providers with platform tokens by staking their LP tokens
- Reward platform token stakers with bonus tokens or a second token
- Lock up founder tokens as "vesting" but while accruing rewards along the way

To deploy the contract, you'll need the Staking Token address, and the Reward Token address. Everything else is either initially constructed or can be added later.

GLHF, submit a pull request or ping me on twitter (https://twitter.com/nateliason) if you find any bugs, vulnerabilities, or issues!

Disclaimer: Do not assume this is production ready. Please do your own testing.
