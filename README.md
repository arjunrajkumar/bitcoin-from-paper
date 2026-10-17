# Bitcoin from Paper

I'm looking to build Bitcoin, without looking at the source code of Bitcoin. So, I'll build it out by looking at the Bitcoin paper, the early forum posts, the cryptography mailing list posts, and by chatting with GPT-6 Astra.

The goal is to get a deep understanding of how Bitcoin works. By first building it out using my solutions, then finding the errors and improving it by looking at the actual Bitcoin code.

For the first version, I'm building a simulation of blocks 0 through 1000. The plan is one block every 0.3 seconds, with a fixed reward of 50 bitcoins per block. That is 1,001 blocks over about five minutes, with a total limit of 50,050 simulated bitcoins.

<a href="https://github.com/arjunrajkumar/bitcoin-from-paper"><ins>GitHub</ins></a>

## Bitcoin Core comparison — Step 3, 17 October 2026

The user authorised Step 3 and chose to update the unspent-output set when a transaction is saved. This is a local simulation rule. Bitcoin Core updates its confirmed set as it applies blocks and handles pending transactions separately. Keep our existing shared database and receipt-only broadcasts. Do not add block acceptance, a mempool, signatures, spending checks or coinbase rules in this step. On 17 October 2026, the user reviewed the code and storage rules, accepted Step 3, and authorised committing, pushing and publishing it on the learning page. Step 4 has not started.

Add `unspent_outputs`, keyed by the pair `transaction_id` and `output_index`, with no separate ID or hidden integer row ID. Each row identifies one available output. Read its amount and spending condition from the immutable source transaction through `UnspentOutput#output`; do not store a second copy of that data. Core stores the output data in its coin database, but this prototype retains the complete source transactions in the same SQL database.

On the first successful model save, remove rows named by the transaction's inputs and add one row for each new output. Put these changes in the same database transaction as the new Transaction record. A validation error, duplicate hash, failed database write or caller rollback must leave both history and the set unchanged. Updating metadata, assigning a block, saving again, receiving or broadcasting must not apply the change again. Keep source transactions and their output lists unchanged when they are spent.

Step 4 still owns rejection of repeated inputs, negative values, missing or spent references and insufficient input value. Until then, removing a reference with no matching row changes nothing, and those structurally valid transactions still save. This set therefore tracks the current stored transactions; it is not proof of valid spending. Use ordinary model creation (`create`, `create!`, `save`, `save!`, node creation and block associations). Bulk inserts or raw SQL bypass model callbacks and are not transaction-creation APIs for this prototype.

The migration requires an empty transactions table rather than guessing prior application order. It preserves blocks, nodes and candidates. A foreign key removes a transaction's own set rows if that source record is deleted; deletion does not restore its consumed inputs and is not chain rollback. Baseline revision is `3fcd249ec4b372c1342f078d828700e52d662a3f`; the unchanged suite passed 87 tests / 1,395 assertions (seed 43759). Development and test both had zero transactions and blocks before migration.

Verification on 17 October 2026:

- The 12 new output-set tests first produced 12 missing-model errors (seed 58587). The three migration tests then produced three missing-migration errors (seed 20053). These were the expected missing-feature results.
- The first implementation run found two stale association results after spending. Creating rows through the source association had retained objects in memory. Creating the set rows directly fixes this without changing the assertions. As with other Rails associations, explicitly preloaded collections still need `reload` after another record changes the database.
- `mise exec ruby@3.4.5 -- bin/rails test test/models/unspent_output_test.rb test/migrations/unspent_output_migration_test.rb` passed 15 tests / 269 assertions (seed 22785). `mise exec ruby@3.4.5 -- bin/rails test` passed 102 tests / 1,664 assertions (seed 59682). `mise exec ruby@3.4.5 -- bin/rails zeitwerk:check` passed.
- Coverage includes all seven ordinary creation paths, partial spends, chained and combined inputs, validation failures, duplicate creation, metadata changes, broadcasts, insertion failure, outer transaction rollback, and preserved later-step spending cases. A deterministic sequence of 36 transactions checks one, two and five outputs against an independent map after each save (seed 17102026). Amounts include zero, signed zero, positive/negative smallest units, a large value and rounding. These finite cases do not prove every possible sequence or concurrent behaviour. Step 4 still owns rejection of conflicting spends.
- Migration checks confirm refusal with existing transactions, preservation of blocks/nodes/candidates, composite keys, foreign keys, position bounds and cascade cleanup after loading the SQL structure. Both empty local databases were migrated. The eight earlier triggers remain unchanged.
- A development console check returned `alice_available: true`, `bob_available: false`, `carol_value: "2.0"`, and `original_outputs: 2` after spending only Bob's output. The check rolled back all writes; transaction and set counts were zero before and after. `git diff --check` passed after removing a generated blank line at the end of the SQL dump. No production logic changed after the full test run.

Look up one available output with `UnspentOutput.find_by(transaction_id: source.id, output_index: 0)`. A missing row returns `nil`. An existing row's `output` returns its value and `script_pub_key`. The database primary key indexes the pair for direct lookup. Saving a later transaction removes only the referenced pairs and adds its own outputs.

The user's corrected learning note is: “I hadn’t realised that every Bitcoin full node keeps a database of UTXOs. That makes sense for faster lookups.” The website first published this learning note separately. The accepted implementation can now be added to the same dated entry with a fixed model diagram and link to its prototype revision.

Rollback: use the Step 2 code with the ignored pre-migration backups in `tmp/unspent-output-baseline/development.sqlite3` and `tmp/unspent-output-baseline/test.sqlite3`. Stop local servers before restoring. Preserve any later records first. Rolling down the new migration only drops the derived set; it leaves transaction history intact, so reapplying it requires an empty transaction table.

## Bitcoin Core comparison — Step 2, 15 October 2026

On 15 October 2026, the user authorised starting Step 2 after publishing Step 1. After discussing Core's scripts and the separate coinbase maturity rule, the user chose **OP_CHECKSIG only for Step 2**. The user then accepted Step 2 and authorised its commit and push, plus publication of a fixed Step 2 diagram and highlighted personal note on Weightless. Preserve the earlier snapshots. Step 3 was subsequently authorised on 17 October, as recorded above.

Replace the old transaction-wide fields with two ordered JSON lists. Each input stores `previous_transaction_id`, a zero-based `output_index`, and `script_sig`. Each output stores `value` and `script_pub_key: { operation: "OP_CHECKSIG", public_key: "..." }`. The signature is an opaque string in `script_sig`; an empty string is allowed, as script verification is not implemented. Public keys remain nonblank strings, not validated cryptographic keys. These named data fields are a simulation format, not executable Bitcoin Script bytes.

Input and output positions come from their list order. They have no independent database IDs. Remove `input_transaction_ids`, `input_count`, `receiver_output_value`, `public_key` and `digital_signature` columns. A transaction hash covers all ordered input and output contents, including proofs and conditions. Keep saved content immutable and block assignment editable. Output values use exact decimal strings in JSON with the existing eight-place rounding and zero normalization. Input references require a 64-character lowercase hash and an integer position from 0 through 4,294,967,295. Reject malformed list items, unknown fields, unsupported operations and nonfinite amounts.

The new hash payload is `["transaction", [[previous_transaction_id, output_index, script_sig], ...], [[value, operation, public_key], ...]]`. Object key order does not affect this fixed array format. An output is identified across transactions by its transaction hash plus its position.

Verify single and multiple inputs/outputs, separate references to outputs 0 and 1, retained source records, exact values, changed content/order changing the hash, rejected edits and atomic failures through direct creation, node creation and block associations. Retain all guessing, candidate, broadcast and hash-identity checks. A new migration must refuse existing transactions or blocks before replacing the empty transaction table; nodes and candidates remain intact.

This step stores the structure only. Repeated references, missing previous outputs and negative values remain accepted until Step 4. No output is marked spent. The unspent-output set, balance checks, signature verification, wallet, script engine, height locks, coinbase creation and coinbase maturity are not added. Core's coinbase waiting period is a separate consensus check, not an alternative to ownership proof; its exact simulation scope will be discussed with the coinbase work.

The six initial structure tests first failed because `Transaction` has no `inputs` attribute (six errors, seed 38016). This is the expected missing-structure result. The accepted Step 1 baseline is `3130526a20891f363f094c5cd773f3b4bd856215`, with 76 tests / 1,055 assertions. Development has zero records in all four domain tables before the new migration.

Each output names its check and the key used for that check. For example, `{ operation: "OP_CHECKSIG", public_key: "alice-public-key" }` means that spending will require a valid signature for Alice's public key. Step 2 stores that rule without checking the signature. `SCRIPT_FIELDS` lists the two required field names; it does not store the rule's values. With only one allowed operation, the operation could be fixed in code. Keeping it explicit makes the stored condition clear.

This current example shows two outputs and a later reference to the second output. The first reference is a placeholder because first-transaction creation and checks for missing outputs are later steps. These calls store data; they do not establish valid spending.

```ruby
source = Transaction.create!(
  inputs: [{ previous_transaction_id: "a" * 64, output_index: 0, script_sig: "prior-proof" }],
  outputs: [
    { value: "3", script_pub_key: { operation: "OP_CHECKSIG", public_key: "alice-public-key" } },
    { value: "2", script_pub_key: { operation: "OP_CHECKSIG", public_key: "bob-public-key" } }
  ]
)

later = Transaction.create!(
  inputs: [{ previous_transaction_id: source.id, output_index: 1, script_sig: "bob-signature" }],
  outputs: [{ value: "2", script_pub_key: { operation: "OP_CHECKSIG", public_key: "carol-public-key" } }]
)
```

Verification on 15 October 2026:

- `mise exec ruby@3.4.5 -- bin/rails test` passed 87 tests / 1,395 assertions (seed 19113). `mise exec ruby@3.4.5 -- bin/rails zeitwerk:check` passed. Coverage includes separate references to outputs 0 and 1, all supported creation paths, exact validation errors, saved-content protection, independent hash examples and retained model behaviour.
- A validation test found that `[nil]` was classified as an empty list. The implementation now checks whether the list is empty, then reports the invalid item. The test assertion was unchanged.
- Generated list checks cover nine combinations of one, two or five inputs and outputs, with amount seed `15102027`. Positions include zero, one and 4,294,967,295. The retained decimal checks cover six boundaries and 40 generated values with seed `15102026`. These finite samples do not prove all inputs or concurrent behaviour.
- Migration checks cover refusal with transactions, blocks or both present; preservation of nodes and candidates; irreversible rollback; and loading the SQL structure with its constraints and eight triggers. Development and test were migrated from empty transaction and block tables. No populated records were converted.
- A local console check created two outputs, then read output 1 through a later input. It returned Bob's key and the exact value `"2.0"`. The check rolled back all writes; all four development tables remained empty. Both local servers returned HTTP 200, and `git diff --check` passed. The final changes after the test run were documentation and removal of a generated blank line in the SQL dump; the full suite was not repeated for those edits.
- At the end of local verification, Step 2 was uncommitted and no website files or fixed diagrams had changed. The user subsequently accepted and authorised publication as recorded above. The unspent-output set and spending checks remain later steps.

Rollback requires the Step 1 code and a matching database backup. The ignored local backups are `tmp/transaction-structure-baseline/development.sqlite3` and `tmp/transaction-structure-baseline/test.sqlite3`. Stop the local server before restoring either database. Preserve any data created after migration before restoring a backup.

## Bitcoin Core comparison — Step 1, 15 October 2026

The user approved Step 1 only: replace integer database identities with hashes, test it, and show fixed before/after diagrams on the local Weightless timeline. Both repositories were kept uncommitted for review. On 15 October 2026, the user accepted the result and authorised committing and publishing both repositories, deploying the Weightless page, then starting Step 2. Each numbered step remains separate. Step 2 still requires agreement on spending-condition and proof representation before implementation.

The original implementation is preserved at `ad6ccc99312c41e16f70ee208e04e47b2e5c5a0f`. Its baseline passed 59 tests / 463 assertions (seed 6695). It has four integer-keyed tables: blocks, transactions, nodes and candidate_blocks. A transaction optionally belongs to a block; a node optionally refers to a separate candidate block. Candidate blocks contain only their ID and timestamps. Previous transaction IDs are a JSON list, not database foreign keys. A block header contains a list of transaction IDs, its creation time and a nested copy of the previous header. The other three model files define an abstract base, the guessing exercise and simulation constants; they have no tables.

Approved identity rules:

- Keep Rails' `id` name, with a lowercase 64-character hash as its only primary key. `block_id`, `candidate_block_id` and the existing input list hold hashes. SQLite domain tables use `WITHOUT ROWID`, so they have no hidden integer row identity. Use `db/structure.sql` to preserve this and the database rules on a fresh load.
- Hash UTF-8 JSON arrays with SHA-256 twice. The first item identifies the data type. Transaction input order is significant. Encode output values as exact decimal strings after the existing eight-place database cast; normalize zero to `"0.0"`. This is our simulation format, not Bitcoin's binary format.
- A transaction hashes `["transaction", input_transaction_ids, input_count, receiver_output_value, public_key, digital_signature]`. Exclude Rails timestamps and block assignment. A block hashes `["block", transactions_hash, header_created_at, previous_header_hash]`. The transaction-list hash uses `["transactions", ordered_transaction_ids]`. The first previous-header value remains `nil`.
- Nodes hash `["node", identity_seed]`; candidates hash `["candidate-block", identity_seed]`. Each seed is 32 random bytes stored once as lowercase hexadecimal. These are simulation identities, not Bitcoin transaction or block content hashes. A candidate still has no header or transactions.
- Saved transaction content, block headers, block height, IDs and identity seeds cannot change. Block assignment and candidate assignment remain editable. Duplicate hashes fail instead of creating a second record. Input hashes must have the correct format; existence, repeats, spending and negative-value checks remain later steps.
- Block height starts at zero and preserves the existing sequential local chain, even with out-of-order timestamps. It is not a key and does not enforce the planned height limit. Default node and transaction lists use hash order. Explicit proof-of-work participant lists retain their supplied order.
- The migration refuses to replace populated tables. Development and the main test database were empty before this change. No data conversion is claimed. Applied historical migrations remain unchanged.

Comparison reference: Bitcoin Core `cce32b16874e85e8a00cfa1a2190f0b6f4dcaf66`, especially `src/primitives/transaction.cpp`, `src/primitives/block.cpp`, `src/hash.h` and `src/net.h`. Core hashes transaction contents and block headers; its local `NodeId` is an integer. The node/candidate rule above is our explicitly approved simulation choice.

Verification on 15 October 2026:

- The first new identity run reported 10 failures and three errors in 13 tests (seed 26709). It exposed the missing hash identities, seeds and content protection. One failure came from a test assertion for `nil`; that assertion was corrected and is not missing-feature evidence. Test setup was also isolated from other classes' fixtures, and nested data snapshots use deep copies.
- The generated decimal check found that SQLite rounded a large output value. A string column alone did not fix it: the adapter still bound a Ruby decimal as a floating-point number. `ExactDecimal` now binds exact decimal text and reads it as `BigDecimal`. The existing eight-place rounding rule remains. The empty local databases were restored from their backups before the revised migration was applied. No populated database was converted.
- `mise exec ruby@3.4.5 -- bin/rails test` passed all 76 tests / 1,055 assertions (seed 60604). Coverage includes fixed independent hash examples, field and input-order changes, duplicate rejection, all four primary keys, both foreign keys, saved-content protection through model and direct writes, retained assignments and broadcasting, height ordering, guessing rules, and exact errors. Migration tests exercise refusal for each populated table, an empty migration, irreversible rollback, and loading the SQL structure with all eight triggers and both foreign keys.
- Decimal coverage uses six boundary values and 40 generated values with seed `15102026`. It includes positive and negative values, zero, signed zero, one hundred-millionth, eight-place rounding, a large value and Unicode text. It checks exact persisted values, hashes and finiteness. Twenty same-time records per seed-based model exercise distinct identities. These samples do not prove collision freedom or all numeric inputs.
- `mise exec ruby@3.4.5 -- bin/rails zeitwerk:check` and `git diff --check` passed. The unchanged guessing exercise still chooses from 0 through 10. No coinbase, input/output records, unspent-output set, balance checks, timer, networking or separate node databases were added. Concurrent block creation and multi-database agreement were not tested.
- The local Weightless page shows fixed baseline and Step 1 diagrams in one grey card, with the user's highlighted note. Desktop, 390px and 320px renderings were checked. The 14 October diagram is unchanged. Both projects remain uncommitted; there was no push or deployment.

Rollback requires the baseline code and a matching pre-migration database backup. The ignored local backups are `tmp/hash-identity-baseline/development.sqlite3` and `tmp/hash-identity-baseline/test.sqlite3`. Stop the local server before restoring a database. The migration refuses automatic rollback; it cannot reconstruct integer identities. Preserve any data added after this step before a restore.

The sections below record earlier learning steps. Their integer IDs, editable content and hash placeholders describe the baseline, not the Step 1 replacement.

## Rules for the planned simulation

`app/models/protocol_rules.rb` defines these values. The total limit is calculated from the inclusive block range and fixed reward.

This step defines the values only. Coinbase creation, the timer, and checks that enforce the block range and total limit will be built in later agreed steps.

## Creating and broadcasting transactions locally

`Node#create_transaction(attributes)` calls `Transaction.create!(attributes)` directly. It uses the existing transaction validation rules. It does not broadcast automatically.

`Node#broadcast_transaction(transaction)` calls `receive_transaction` on every other saved node. For now, receiving only writes `Node <id> received transaction <id>` to the Rails log. Each call reports receipt, including repeated broadcasts.

For this learning step, all nodes share one local database. Each transaction is stored once. Nodes do not keep their own transaction lists or copies. A broadcast includes all other nodes saved at the time of that call.

Use saved nodes and a saved transaction for a broadcast. This example requires an existing transaction to reference. Creating the first transaction is a later step.

```ruby
sender = Node.create!
receiver = Node.create!
previous_transaction = Transaction.first!

transaction = sender.create_transaction(
  public_key: "receiver-public-key",
  receiver_output_value: "2",
  input_transaction_ids: [previous_transaction.id]
)

sender.broadcast_transaction(transaction)
# Check log/development.log for the receiving node's message.
```

These calls run locally, one at a time. They do not generate keys or signatures, check spending rights, or use a real network. Keeping received transactions for block selection is a later step; the current block placeholder still reads all stored transactions.

On 15 October 2026, the user requested direct transaction creation and removal of the per-node transaction lists. Reverted the development join-table migration and removed its uncommitted file. The development database had no blocks, nodes, transactions or links before removal. The separate test rollback failed because the migration file was already removed. After the test run, a direct database check confirmed that both development and test contain only the original domain tables and use migration version `20261015000014`.

Revised checks first failed on the retained table, the dependency on a saved node, and the missing receipt messages (17 tests / 72 assertions, five failures and one error, seed 64939). The final `mise exec ruby@3.4.5 -- bin/rails test` run passed 53 tests / 432 assertions (seed 57972). Checks cover direct creation, existing validation failures, separate broadcast, receipt by all other nodes, repeated calls, later nodes, no other nodes, and broadcasting only the selected transaction. Rails loading and whitespace checks passed. Real network delivery and concurrent broadcasts were not tested.

## One candidate block per node

Each node has one optional `candidate_block` reference to a separate `CandidateBlock`, stored in `nodes.candidate_block_id`. A node starts without a candidate. Assigning another candidate replaces the reference; clearing it leaves the candidate records intact. The database requires a supplied reference to point to an existing candidate block.

```ruby
candidate = CandidateBlock.create!
node.update!(candidate_block: candidate)
node.candidate_block
```

This step adds the separate model and relationship only. `CandidateBlock` stores an ID and timestamps. It does not inherit from `Block`, build a header, link to a previous block, or collect transactions yet. Creating a node does not create a candidate automatically.

On 15 October 2026, replaced the earlier uncommitted reference to `Block` with the separate candidate model. Development and test had no saved nodes or candidate assignments. Rolled back the earlier migration in both databases before replacing it with `20261015000015_create_candidate_blocks.rb`. Revised checks first failed because the separate model and table were missing, and the old relationship still accepted a regular block (15 tests / 35 assertions, two failures and five errors, seed 15964).

Applied the new migration in development and test. All 59 tests / 463 assertions passed (seed 6484). Checks cover separate candidate records, optional assignment, replacement, clearing, and rejection of regular blocks or missing candidate IDs. Rails loading and whitespace checks passed.

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
