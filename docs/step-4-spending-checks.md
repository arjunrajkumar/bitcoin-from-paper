# Step 4: transaction spending checks

## Scope and review

Implement only Step 4. The baseline is `2ec4a37e036b4cb73cc5e407517018df8c36b302`; its unchanged suite passed 102 tests / 1,664 assertions (seed 21153). On 17 October 2026 the user approved these checks and test-only prepared starting outputs. They requested keeping both repositories uncommitted during review and keeping work records out of the README. After reviewing the checks, they accepted Step 4 and authorised its commit, push and live learning-page publication. This document holds the Step 4 contract and evidence. Discuss Step 5 before implementing it.

## Behaviour

- Reject repeated previous-output pairs, negative output values, missing or spent outputs, and total output value greater than the available input value.
- Read amounts from the stored source outputs. Use exact decimals and the existing eight-place rounding for nonnegative values. Reject negative values before rounding can turn them into zero. Zero and signed zero remain allowed.
- Treat missing and spent references as the same availability error. Validate structure before reading nested fields or looking up amounts.
- Check spending during creation. Require each input removal to delete exactly one row in the same database transaction as the new history and outputs. A failed removal rolls back earlier removals and the new record.
- Revalidation, failed writes, competing spends and caller rollback leave no partial changes. Metadata updates and receipt-only broadcasts remain unchanged.
- Support ordinary model saves, node creation and block associations. Raw SQL, bulk inserts and saves that skip validation are not transaction-creation APIs.
- Use explicit prepared test snapshots until Step 5 supplies coinbase. These bypass creation callbacks and include synthetic hash IDs for retained hash vectors. Add no production funding helper or exception for missing references. Do not seed or rewrite development data.
- Replace earlier expectations that deliberately accepted invalid spending. Retain hash, structure, broadcast, migration and rollback coverage.
- Defer signature checks, coinbase, block acceptance, fee payout, networking and mining.

## Verification

Test single and combined inputs, separate output positions, exact and surplus input value, zero and decimal boundaries, all rejection cases through every supported creation path, stale candidates, conflicting saves and rollback on failed removal/insertion. Use deterministic generated amounts and spending sequences with independent expected values.

- Initial spending tests: 12 tests / 83 assertions, nine expected failures, no errors (seed 10137). Valid spending cases were already green.
- The first concurrent-process test failed during database setup, before either spend. It did not establish a missing-feature result. Investigation found simultaneous journal-mode setup on the new temporary database.
- Set the temporary database to WAL mode before starting the two independent processes. Both validate their candidates, then receive a shared start signal. Exactly one saves; the other reports the missing-or-spent input. The database contains only the source and winning payment. This is one controlled concurrent case, not a proof of all schedules or other database adapters.
- The first full run with prepared starting state had 11 errors (115 tests / 1,972 assertions, seed 36591). The old YAML fixtures had double-encoded their JSON lists. Removed the extra string encoding without changing their IDs, values or keys. Added explicit checks for list types, exact values and the independent content hashes. No production coercion was added.
- Two further tests reproduced partial writes when a caller caught a failure inside its own transaction (two tests / five assertions, seed 37354). New records now use a separate rollback boundary in `save` and `save!`. A false return also rolls back. Saved-record metadata paths still use the inherited methods. Both recovery tests pass without relaxing their assertions.
- The focused spending/concurrency command passed 15 tests / 335 assertions (seed 26498). The final `mise exec ruby@3.4.5 -- bin/rails test` passed 118 tests / 2,048 assertions (seed 18224), with no failures, errors or skips. `mise exec ruby@3.4.5 -- bin/rails zeitwerk:check` and `git diff --check` passed.
- Coverage includes seven creation paths; same/different source transactions; separate output positions; exact totals, fees, zero, signed zero, one-unit boundaries and small negative values; repeated/missing/spent references; stale validation; failed deletes/inserts; nested recovery; metadata, hashes, broadcasts and migrations. The generated amount matrix uses seed 17102027 with 1/2/5 inputs and outputs and totals one unit below/equal/above the available value. The retained 36-save set sequence uses seed 17102026 with valid prepared funding. The hash cases retain seed 15102026; negative amounts now require rejection, while nonnegative amounts retain independent digest checks. These are finite exercised domains.
- Prepared funds are confined to tests. Read-only development checks found zero transactions, available outputs, blocks, nodes and candidates. No schema or dependency changes, data migration, commit, push or deployment was made. The local website note has separate request/browser verification.
- Release verification after acceptance: `mise exec ruby@3.4.5 -- bin/rails test` passed 118 tests / 2,048 assertions (seed 61013), with no failures, errors or skips. `mise exec ruby@3.4.5 -- bin/rails zeitwerk:check` and `git diff --check` passed. Reviewed the implementation, new tests and fixture changes. No implementation changes were needed after review. This repository has no GitHub Actions workflow or separate hosted runtime; publication pushes the prototype source to GitHub. Weightless publishes the learning entry separately.

## Learning note

“It’s early days reviewing the code, but it’s good to know it’s just code. There are lots of checks and edge cases to handle so a faulty or malicious wallet cannot misuse it.”

Publish the accepted note above the earlier output-tracking entry. State the implemented checks and the remaining signature/coinbase limits.
