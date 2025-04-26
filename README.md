## Tobasco
Tobasco is a proof-of-concept implementation of a preconf protocol that enforces ToB L1 inclusions. 

![](images/logo.png)

### How to enforce Top of Block (ToB) inclusions?

Assuming the `Preconfer` issued the preconf there are two types of safety faults:

1. They included the transaction in a different position in the block, aka the Rest of Block (RoB) 

    **mitigation**: `onlyTopOfBlock()` modifier reverts if the transaction is not ToB, preventing safety faults
    
2. They proposed a block with a *different* transaction at ToB
    
    **mitigation**: `onlyTopOfBlock()` did not record a submission during that block and the `Challenger` can slash the `Preconfer` via the [`URC`](https://github.com/eth-fabric/urc) contract.

If there's a *liveness fault* and the preconfer misses their slot the `Preconfer` is slashed for the same reason as 2.

### Testing
![](images/testing.png)

The image demos Tobasco in action:
- An `OracleExample` contract has been deployed and implements the `onlySubmitter` and `onlyTopOfBlock` modifiers so that it's `post()` function only succeeds if it lands ToB.
- On the top right, a local anvil node publishes blocks every 20s
- On the top left, an ETH transfer lands at the ToB
- On the bottom left, the call to `post()` reverts with a `NotTopOfBlock` error
- On the bottom right, we inspect the block and see that the `post()` transaction did land second.

Note if recreating this test, modifying the transaction gas limit in a Foundry script isn't working. The following command will work once the `ADDRESS` and `BLOCKNUM` environment variables are set:

```bash
cast send $ADDRESS  --rpc-url 127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --gas-limit 30000000 "post(uint256,uint256)" 100 $BLOCKNUM
```