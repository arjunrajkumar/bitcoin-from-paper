# Transactions

## Initial understanding

These questions asked by ChatGPT are my starting point. These answers are written in my own words before building each small step, including anything I'm unsure about.

- **What do I think a transaction is?**

  A transaction sends bitcoin from one or more wallet addresses to one or more wallet addresses.

- **What information should a transaction contain, and why?**

  - **Input wallet addresses:** One or more wallet addresses belonging to the sender.
  - **Output wallet addresses:** The person being paid (the receiver) and the change to be paid back to the sender.
  - **Miner fees:** The fees to pay the miner. The difference between input and output.
  - **Digital signature for all the input wallet addresses:** So that the digital signature can unlock the input wallets to transfer bitcoins.

- **What should happen when someone creates a transaction?**

  When someone creates a transaction, it needs to be broadcast so that all the nodes can learn about the new transaction, verify it, and include it in the node's memory pool.

- **What makes a transaction valid or invalid?**

  - If the digital signature provided by the sender is not valid.
  - If it has already been added to the blockchain.
  - If it has already been added to a node's memory pool.
  - If the receiver's wallet address is missing or wrong.
  - If there are no funds in the sender's wallets to pay the receiver.

- **How should a transaction become part of a block?**

  A node needs to first verify all the transactions, verify the digital signature, verify the output wallet, then add it to its memory block. Then a miner that has completed the proof of work has to include it in the candidate block. Then, there needs to be more than 10+ blocks above it to be confident that this chain is the longest blockchain.

- **What do I expect to happen in a normal example?**

  Suppose I have 5 BTC and want to pay someone 2BTC. The inputs will be my 5BTC from my wallets. The out is the receives wallet. Ther will also be a fee to pay the miner. Once I confirm this transaction, it will be broadcasted to all the nodes, and picked by mining nodes. Then when a mining node creates a candidate blc, it be included in this candidtate block.

- **What could go wrong, and how should my solution handle it?**

  - If a node recieves the transaction adter it has already included it in its memory pool, it should not repsond.
  - If a node receives the trasaction after it has already been included in the blockchain, it should not repond.
  - If a node receives an incorrect transaction. i.e. digital signatures are wrong, it should be dropped.

## Error correction

I'll keep my original answers so I can see how my understanding changes. For each correction, I'll record:

- **Original idea:** What did I believe, and why?
- **Problem found:** What example, question, or result challenged that idea?
- **Type of error:** Was my understanding wrong, did my code fail to follow my idea, or both?
- **Changed understanding:** What do I now think, and why is it an improvement?
- **Check:** What experiment or test supports the change? What is still uncertain?
- **Source and date:** When did I change my mind? Was it after discussion, an experiment, reading the paper or early discussions, or later reading Bitcoin's source code?

[Back to the README](../README.md)
