## Tobasco
Tobasco is a proof-of-concept implementation of a preconf protocol that enforces ToB L1 inclusions. 

### How to enforce Top of Block (ToB) inclusions?

Assuming the `Preconfer` issued the preconf there are two types of safety faults:

1. They included the transaction in a different position in the block, aka the Rest of Block (RoB) 

    **mitigation**: `onlyTopOfBlock()` modifier reverts if the transaction is not ToB, preventing safety faults
    
2. They proposed a block with a *different* transaction at ToB
    
    **mitigation**: `onlyTopOfBlock()` did not record a submission during that block and the `Challenger` can slash the `Preconfer` via the [`URC`](https://github.com/eth-fabric/urc) contract.

If there's a *liveness fault* and the preconfer misses their slot the `Preconfer` is slashed for the same reason as 2.
