# Bitcoin from Paper

I'm looking to build Bitcoin, without looking at the source code of Bitcoin. So, I'll build it out by looking at the Bitcoin paper, the early forum posts, the cryptography mailing list posts, and by chatting with GPT-6 Astra.

The goal is to get a deep understanding of how Bitcoin works. By first building it out using my solutions, then finding the errors and improving it by looking at the actual Bitcoin code.

<a href="https://github.com/arjunrajkumar/bitcoin-from-paper"><ins>GitHub</ins></a>

## Current learning step: block headers

A block contains transactions. On 15 October 2026, the user narrowed this step to the current block and its header. The JSON header contains:

- `transactions_hash`: the supplied transaction hash, initially unset.
- `created_at`: the block's creation time, copied from Rails' existing `created_at` field only when the block is first created.

The block's `created_at` field is the source for the header's initial time. Updating the transaction hash and calculating hashes leave that time unchanged. Updates do not copy the time into the header again; replacing the whole header preserves the supplied replacement as-is. An unsaved block has no creation time yet. The separate `timestamped_at` and stored `header_hash` fields are removed. The previous-block relationship, its helper methods, previous-hash storage, database constraints and related tests are removed at the user's request. Linking blocks is outside this learning step. Previously applied migrations remain as history.

Both hash methods remain placeholders. `calculate_transactions_hash` returns the block's transaction IDs. `calculate_header_hash` returns the whole header object. Neither method changes stored values or uses a fresh current time. Later, the transaction hash will cover transaction contents, and the header hash will cover the transaction hash and creation time. IDs alone cannot detect edits to transaction contents. Filling in the transaction hash, actual hashing and verification are later steps. A stored time alone does not establish proof of existence.

The older Transactions diagram on Weightless remains a fixed record. It is not updated by this model change.

Verification on 15 October 2026:

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
