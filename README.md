# Bitcoin from Paper

I'm looking to build Bitcoin, without looking at the source code of Bitcoin. So, I'll build it out by looking at the Bitcoin paper, the early forum posts, the cryptography mailing list posts, and by chatting with GPT-6 Astra.

The goal is to get a deep understanding of how Bitcoin works. By first building it out using my solutions, then finding the errors and improving it by looking at the actual Bitcoin code.

For the first version, I'm building a simulation of blocks 0 through 1000. The plan is one block every 0.3 seconds, with a fixed reward of 50 bitcoins per block. That is 1,001 blocks over about five minutes, with a total limit of 50,050 simulated bitcoins.

<a href="https://github.com/arjunrajkumar/bitcoin-from-paper"><ins>GitHub</ins></a>

## Rules for the planned simulation

`app/models/protocol_rules.rb` defines these values. The total limit is calculated from the inclusive block range and fixed reward.

This step defines the values only. Coinbase creation, the timer, and checks that enforce the block range and total limit will be built in later agreed steps.

## Proof-of-work assumptions and method

For the proof-of-work exercise, the program chooses a target number from 0 to 10, inclusive. Each node guesses once per round. The program collects every guess, then checks them in order. The first matching entry wins. If no guess matches, the program chooses a random node from that round.

The program controls which nodes take part and runs each round locally. A node can try again only after all nodes have guessed. This simulation uses no real hashing or CPU race. Network communication and connecting the winner to a block come later.

`ProofOfWork#generate_number` chooses an integer from 0 through 10 inclusive and keeps it in that object's memory. `matches?(received_number)` returns true only for the matching integer. Checking a guess does not generate a new target. Before generation, every guess returns false. The shared number range is defined in `ProtocolRules`.

The [whitepaper's Section 5](https://bitcoin.org/bitcoin.pdf) calls the participants nodes, including those finding proof of work. The `Node` model stores an ID and Rails timestamps. `Node#guess` generates one integer in the same range. These are local records for the simulation.

`ProofOfWork#find_winner` runs one round. It reads all saved nodes in ID order and collects one guess from each before checking any answer. The first matching entry wins. If no guess matches, it picks a random participant. With no participants, it returns `nil`. It requires a generated target and raises `ArgumentError` with `Generate a number before starting a round` if there is none.

An optional node list can be supplied for a local round. Its order decides which matching entry wins. Duplicate records of the same node count once. Each later call starts another round, after the previous call has collected all guesses. Call `generate_number` to change the target; `find_winner` leaves it unchanged.

```ruby
3.times { Node.create! }
proof = ProofOfWork.new
proof.generate_number
winner = proof.find_winner
winner.id
```

Rounds run one call at a time. Node records are saved, but targets, guesses and winners are not. This exercise does not protect block contents. Concurrent requests, block creation and rewards are later steps.

Verified the node round on 15 October 2026. The nine new tests first reported the missing `Node` model and `find_winner` method (seed 41166). Applied `20261015000014_create_nodes.rb` locally. Updated the existing exact table-list assertion to include the requested nodes table. `mise exec ruby@3.4.5 -- bin/rails test` then passed all 45 tests / 386 assertions (seed 24477). Checks cover collecting every guess before selection, first-match order, duplicate records, repeated rounds, empty rounds, the required target, and every fallback selection among three nodes for all 11 targets. These are local, sequential checks. Rails loading and whitespace checks passed.

Verification of the initial guessing exercise on 15 October 2026: all 36 tests / 282 assertions passed (seed 24120), including all 121 target/guess pairs from 0 through 10, invalid guesses, checking before generation, and keeping the target unchanged during checks. Rails loading and whitespace checks passed.

## Current learning step: block headers

A block contains transactions. On 15 October 2026, the user added a simple chain after building the current block's header. The JSON header contains:

- `transactions_hash`: filled by `calculate_transactions_hash` when the block is first created. This is currently a list of transaction IDs, because hashing is deferred.
- `created_at`: the block's creation time, copied from Rails' existing `created_at` field only when the block is first created.
- `previous_header_hash`: the result of calling `calculate_header_hash` on the last saved block. The first block uses `nil`.

`before_create :build_header` fills all three values on the first save. For this first sequential, local chain, the last saved block means the row with the highest database ID, regardless of its supplied creation time. Later saves do not recalculate the link. There is no stored `header_hash`, separate `timestamped_at`, `previous_block` association or hash-based database constraint. Concurrent block creation and choosing between competing chains are later steps. The migration changes only the JSON default; it does not change existing headers.

For this learning step, `potential_transactions` returns all stored transactions in ID order, including transactions already assigned to blocks. It does not assign or move transactions. Receiving transactions from the network and selecting which ones to consider are later steps. An empty transaction store produces an empty list. Later arrivals and updates do not rebuild the saved header; replacing the whole header preserves the supplied replacement as-is. An unsaved block has no creation time yet. Previously applied migrations remain as history.

Both hash methods remain placeholders. `calculate_transactions_hash` returns only the IDs from `potential_transactions`. `calculate_header_hash` returns the whole header object, including its previous link. As a result, `previous_header_hash` temporarily stores a nested copy of the previous header, not a real hash. Changing an earlier block later does not change this saved copy. Neither calculation method changes stored values or uses a fresh current time. Later, the transaction hash will cover transaction contents, and the header hash will cover the transaction hash, creation time and previous header hash. IDs alone cannot detect edits to transaction contents. Actual hashing and verification are later steps. A stored time alone does not establish proof of existence.

The older Transactions diagram on Weightless remains a fixed record. It is not updated by this model change.

Verification on 15 October 2026:

- Added the previous-header link during block creation. Revised Block checks first failed as expected (17 tests / 44 assertions, seven failures and three missing-accessor errors, seed 16283). After applying `20261015000013_add_previous_hash_to_block_headers.rb`, all 31 tests / 134 assertions passed (seed 16054). Checks cover the first null link, a complete three-block chain using the placeholder, highest-ID selection with out-of-order creation times, and saved links that remain unchanged after earlier or later edits. These checks do not verify cryptographic hashes or concurrent creation.
- Before the user removed the backfill, an isolated in-memory SQLite probe passed 11 checks for migration, rollback, repeat migration and loading `db/schema.rb`. Development had zero blocks and transactions before migration. The user then requested a simple default-only migration because this is a new project with no production data. Removed both JSON data updates and used a reversible `change` method.
- Added `potential_transactions` as the source for the transaction-hash placeholder. It currently reads all stored transactions in ID order. Revised Block checks first failed as expected (14 tests / 37 assertions, four failures and two missing-method errors, seed 29685). All 28 tests / 120 assertions then passed (seed 31433). Checks cover empty candidates, all stored transactions including already assigned ones, a smaller candidate list distinct from assigned transactions, unchanged transaction assignments, and a saved header that does not change when new candidates appear. No networking or schema changes were added.
- Added `before_create :build_header` to store the transaction-ID placeholder and creation time together. Revised Block checks first failed as expected (13 tests / 41 assertions, four failures, seed 8458). The callback then exposed that `pluck` returned no assigned IDs before the block was saved; reading the assigned transaction objects with `map(&:id)` fixed this. All 27 tests / 110 assertions passed (seed 12567), including empty, single and multiple assigned transactions, unchanged headers after later additions, and retained transaction associations. Whitespace checks passed. No schema change was needed.
- At the user's request, removed the update callback so creation time is copied only on creation. The revised replacement-header check failed before removal (one test / one assertion, seed 9662). The final `mise exec ruby@3.4.5 -- bin/rails test` run passed all 26 tests / 105 assertions (seed 30054).
- Before the change, all 32 tests / 154 assertions passed (seed 52143). The revised Block checks then failed as expected: 12 tests / 31 assertions, eight failures, seed 62801. The failures showed the old fields, header shape and time inputs were still present.
- Applied `20261015000012_simplify_block_headers.rb` locally. Development had no blocks or transactions before the migration. The migration removes the old hash fields, their indexes and previous-block foreign key, removes the previous hash from existing JSON headers, and copies each block's existing creation time into its header. It does not change the transaction-to-block relationship. It cannot restore discarded hash or timestamp values on rollback.
- `mise exec ruby@3.4.5 -- bin/rails test` passed all 26 tests / 105 assertions (seed 25798). The reduced count reflects the requested removal of previous-block behavior and its tests. Current checks cover automatic and supplied creation times, microsecond precision, later updates, replacement headers, unchanged values during hash calculation, and the retained transaction associations.
- An isolated in-memory SQLite probe passed 12 checks for migration and loading `db/schema.rb`. Three sample blocks and one transaction retained their IDs, creation/update times, transaction hashes and transaction-to-block links. The old block columns, indexes and foreign key were absent. The transaction foreign key remained enforced. `bin/rails zeitwerk:check` and whitespace checks passed. No website files or diagrams changed.

Verification on 14 October 2026:

- JSON-header follow-up: the revised Block checks first failed because the JSON attribute and transaction-hash method were absent (18 tests / 52 assertions, one failure and eight errors, seed 15350). Applied `20261014000011_store_block_headers_as_json.rb` locally. `mise exec ruby@3.4.5 -- bin/rails test` then passed all 32 tests / 154 assertions (seed 52854). Checks cover JSON persistence, previous-block assignment and lookup, direct JSON edits after loading the association, clearing the link, eager loading, the saved timestamp, and the existing database constraints. Both hash methods still return inputs; these tests do not verify real hashes.
- An isolated in-memory SQLite probe passed 16 checks for migration, rollback, repeated migration and loading `db/schema.rb`. Four sample blocks (including a linked pair and two unset hashes) and one transaction kept their existing data. The JSON value supplied the previous-block reference, and the loaded schema enforced unique hashes and existing references. `bin/rails zeitwerk:check` passed. Both local servers returned HTTP 200. No website or diagram changes were made for this step.
- Previous-block follow-up: revised Block checks first failed because the association and database rules were absent (15 tests / 37 assertions, three failures and four errors, seed 50773). Before migration, development had zero blocks, zero transactions, no duplicate supplied hashes and no missing previous references. Applied `20261014000010_link_blocks_by_header_hash.rb` locally.
- `mise exec ruby@3.4.5 -- bin/rails test` then passed all 29 tests / 131 assertions (seed 62653). Coverage includes assignment through the previous-block object, lookup through a supplied hash, a three-block chain, unset hashes, exact database errors for duplicate hashes and missing references on insert/update, and protection of referenced hashes from change/deletion. The transaction-ID placeholder and prior association checks still pass. `bin/rails zeitwerk:check`, migration syntax and whitespace checks passed. No website, commit, push or deployment changes were made.
- Transaction-ID follow-up: the revised Block checks failed as expected while the method still returned `nil` (ten tests / 31 assertions, two failures and one error, seed 51052). After returning `transactions.pluck(:id)`, `mise exec ruby@3.4.5 -- bin/rails test` passed all 24 tests / 98 assertions (seed 15230). Checks cover empty, single and multiple transactions, exclusion of another block's transactions, loaded and unloaded associations, and unchanged stored header fields. Whitespace checks passed. No schema, website or deployment changes were needed.
- The existing Block and Transaction baseline passed 18 tests / 78 assertions (seed 6745). The new Block checks then produced four expected errors because the header fields did not exist (eight tests / 16 assertions, seed 1962).
- The first migration attempt stopped on a missing `end` before any database change. Fixed the syntax, then applied `20261014000009_add_header_fields_to_blocks.rb` locally. Development counts stayed at zero blocks and zero transactions.
- `mise exec ruby@3.4.5 -- bin/rails test` passed all 22 tests / 95 assertions (seed 8790). Coverage includes unset fields, the first header, a populated block linked by the prior hash, the empty method and the existing transaction associations. These checks use supplied sample hashes; they do not verify hashing or timestamp proof.
- `mise exec ruby@3.4.5 -- bin/rails zeitwerk:check`, migration syntax and whitespace checks passed. The local server's `/up` check returns 200. No website files or older diagrams changed in this step. No commit, push or deployment was made.

## Background knowledge

[Building my background knowledge on Weightless](https://weightlessapps.com/background-knowledge): dated model diagrams and short notes as my understanding changes.

## References

- [Bitcoin: A Peer-to-Peer Electronic Cash System](https://bitcoin.org/bitcoin.pdf)
- [Early cryptography mailing-list discussion](https://satoshi.nakamotoinstitute.org/emails/cryptography/17/)
