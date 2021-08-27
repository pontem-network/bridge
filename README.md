# Diem ↔ Pontem Bridge

**THIS PROJECT IS NOT READY FOR PRODUCTION YET, IT'S IN ACTIVE DEVELOPMENT**

Requirements:
    * [Dove](https://github.com/pontem-network/move-tools/releases)

This document describes research around building a bridge between Diem and Pontem Network. 

Current goal is to allow transfer assets (mostly standard ERC20 like tokens) between both networks. The bridge is going to be based on Proof of Authority currently and later could be swapped with Governance or even PoS validators. 

As both networks utilize Move Virtual Machine, means we are going to implement smart contracts written in Move language, validator nodes (that will organize validators based on information from both chains), and documentation.

Similar projects:

- [Gravity Bridge](https://github.com/cosmos/gravity-bridge)
- [Chain Bridge](https://github.com/ChainSafe/ChainBridge)

During implementation of the bridge we are going to fork Chain Bridge and implement support for both Diem and Pontem network, such a way we wouldn't need to build additional validator logic that is already implemented in Chain Bridge.

## Bridge Contract

### Admin and Relayers

The Current bridge contracts would have a list of authorities (PoA) that process and approve new transfers between chains, we call authorities relayers. Also, The bridge contract will have a maximum number of relayers, required threshold (how much votes needed to process transaction), and fees that should be paid to relayers.

The bridge contract has an admin account that can manage relayers lists: add new relayers, remove them. Admin also can pause bridge transfers, change the rest of the configuration of the bridge.

Fees can be paid only in one native coin in a specific blockchain, for Diem it's XDX, for Pontem it's PONT coin. Fees also configurable by admin.

The bridge also has a list of tokens that are supported by bridge and a list of those that should be burned during transfer or just locked, such functionality is managed by an admin account.

In the future version we can change admin address to governance one, meaning it will be the Substrate module address. Also we could replace relayers with PoS validators by implementing special native functions bindings for querying PoS validators/collators from Move smart contract.

### Transfer to another network

During transfer of tokens from blockchain A to blockchain B user should call specific function of Bridge smart contract and pass there following arguments:

- NetworkID - the id of the network, u8.
- Coin - which coin to transfer. Usually generic type.
- Amount - amount of coins to transfer, u64.
- RecipientAddress - address of recipient on another network, should vec<u8>.
- Metadata - just additional metadata, vec<u8>.

The transaction should contains fee to pay validators. 

Once the transaction contains a transfer call, the smart contract should emit an event that contains id of deposit (nonce), coin, amount and recipient address. Relayers nodes catching events on chain A and creating new proposals for issue tokens on chain B.

### Proposals

Once a bridge receives a new transfer on the blockchain A it creates a new proposal on the blockchain B and initiates a voting period on that proposal. A proposal usually contains following information:

- Coin - which coin to mint/unlock. Usually generic type.
- ID - id of proposal, u128. It's a deposit nonce on another network.
- Amount - amount of coins to transfer, u64.
- RecipientAddress - address of recipient on another network, should vec<u8>.
- Metadata - just additional metadata, vec<u8>.

So all relayers can vote on proposals and if proposals successfully voted, it would be executed (means tokens should be minted or unlocked on another network).

The contracts determine a successful voting on a proposal if votes for a specific proposal reached a threshold configured in smart contract.

### Fees

Fees split between all relayers during deposit. Relayers can withdraw their fees later by sending another transaction. Remainder will be stored and will be used to distribute fees when possible.

### Smart Contracts

As both networks support Move language and Move VM, we implemented Bridge contract that can be found in the current repository and can be used on both networks.

TODOs:

* Missing fees distribution.
* More tests.

**About creation of proposals and round-robin**
 
In Diem any information must be published under account. So, we are going to use round-robin to detect which relayer account should create a proposal. There could exist only one proposal on account. For implementation see [create_proposal](/modules/Bridge.move#321) function. Implementation with vectors could use too much gas. We are still working on it, and we think we can improve it in future with different approaches like HashMap.

### Tests

    dove test

### LICENSE

Apache 2.0
