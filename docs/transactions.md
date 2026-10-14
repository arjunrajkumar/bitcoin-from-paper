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

### Input and receiver value comparison — 14 October 2026

- **Original idea:** Require `total_input_value <= receiver_output_value`.
- **Problem found:** This would allow five BTC of inputs to fund a six BTC receiver value.
- **Type of error:** The comparison in the proposed rule was reversed.
- **Changed understanding:** The user confirmed `total_input_value >= receiver_output_value` after discussion. The receiver value must not exceed the input total.
- **Check:** Creation tests accept equality and a lower receiver value, and reject a higher receiver value. Ownership, signatures, input links and fee calculation remain separate work.
- **Source and date:** Discussion and the user's explicit correction on 14 October 2026. No Bitcoin implementation source was consulted.

## Build steps

### Keep only attribute validation — 14 October 2026

- The user asked to remove `inputs_belong_to_same_sender`, `input_value_covers_receiver_output_value` and `digital_signature_matches_input_public_keys`, their validation calls and their related tests. The user also authorised committing this change.
- Keep the three creation checks exactly as requested: presence of `input_transaction_ids`, presence of `public_key`, and numericality of `receiver_output_value`.
- Keep the `total_input_value` calculation and its tests. It runs only when called, not during creation. Missing input records can therefore be stored in the list; an explicit total calculation still raises `ActiveRecord::RecordNotFound` for them.
- Remove the input/output comparison tests and custom non-finite-value rejection tests. Remove creation-rejection assertions from tests that also cover the retained total calculation. Keep storage tests and the three attribute-validation checks.
- Full transaction verification and the decision about where it belongs remain deferred. This change does not add a wallet or move the checks elsewhere.
- Before implementation, the retained decimal-storage test failed as expected because the old comparison still rejected the stored receiver value (seed 21935). After removal, `bin/rails test` passed all 20 remaining tests / 79 assertions (seed 34322). The stored attributes, three retained checks and calculated-total behavior remain covered.
- The scoped diff and `git diff --check` passed review. No migration was needed. The user authorised this local commit; no push or deployment was requested.

### Remove the saved-input validation — 14 October 2026

- The user asked to remove `validate :input_transactions_are_saved, on: :create`. Remove both the callback and its method, including its integer-list and record-existence checks.
- Keep input-list presence, public-key presence, receiver-value checks and the existing ownership/signature placeholders.
- The calculated total still calls `Transaction.find(input_transaction_ids)`. If a referenced record is missing, this lookup raises `ActiveRecord::RecordNotFound`, including during creation. Do not replace the removed validation with another check or silently use a partial total.
- Remove the two tests for the removed validation. Update the existing missing-record calculation test to check the lookup error during creation and confirm that no transaction is saved.
- Baseline: all 27 tests / 172 assertions passed (seed 56255). The changed calculation test first failed as expected because the old validation still returned an error instead of allowing the lookup to run (seed 2019). After removal, `bin/rails test` passed all 25 tests / 136 assertions (seed 57870).
- The scoped changes and `git diff --check` passed review. No migration was needed. No CI run, commit, push or deployment was made.

### Calculate the input total when needed — 14 October 2026

- The user asked to remove the stored `total_input_value`. Keep that name as a method that calculates the sum of the referenced transactions' `receiver_output_value` fields when called.
- Remove only the total column. Keep `input_count`, the plain `input_transaction_ids` list and the receiver value. Do not add fee calculation in this step.
- Calculate with decimal values in Ruby. Query the current input records on each call; do not cache or save the total. Each referenced transaction contributes once even if its ID appears repeatedly in the list. The list itself is unchanged.
- Keep the creation rule `total_input_value >= receiver_output_value`. A missing input record must not produce a partial total. A missing or non-finite input value must fail the creation checks. The existing ownership and signature placeholders remain unchanged.
- Replace tests for supplying a total with tests for calculating it from saved input values. Keep the decimal comparison boundaries and other field checks. Baseline: all 20 tests / 159 assertions passed (seed 40678). The new calculation tests first produced six expected failures (seed 35719).
- The first implementation run exposed a test assumption about stored NaN. A database round-trip confirmed that SQLite stores NaN as `NULL`, while positive and negative infinity remain decimal infinities. The test now asserts that NaN becomes a missing value and is rejected as nonnumeric. Both infinities must still be rejected as non-finite. No rejection was removed.
- Final verification: `bin/rails test` passed all 27 tests / 172 assertions (seed 24252). Checks cover one and several inputs, exact fractional sums, fresh reads after changes, repeated IDs, absent records, missing/non-finite values and all 16 earlier comparison pairs from zero through three hundred-millionths of a BTC. These examples do not prove every possible numeric case.
- The local column-removal migration, `bin/rails zeitwerk:check` and `git diff --check` passed. The scoped changes were reviewed. No CI run, commit, push or deployment was made.

### A plain list of input transaction IDs — 14 October 2026

- The user asked to replace `has_many :inputs` with a plain list on the new transaction. Store `input_transaction_ids` as a JSON list, such as `[10, 11, 12]`. Rails reads it as a Ruby array.
- Remove the `spent_by_transaction_id` column and its association. Saving the new transaction stores only its list and does not update the older transactions.
- Keep the creation rule that at least one input refers to an already-saved transaction. Require a nonempty list of integer IDs and reject missing records. Preserve the order and any repeated IDs as supplied; spent-status and duplicate-input rules are deferred.
- Retain the other fields and creation checks. Counts and totals are still supplied separately. The ownership and signature methods still return `true` as requested. No new lookup helper or association is added.
- Baseline: all 20 tests / 130 assertions passed (seed 8084). The development database contained zero transactions and zero input links. Both local databases were checked for stored input links before replacing the uncommitted reference-column migration. No transaction records were deleted.
- The seven list tests first failed because the field was missing and the old input error remained (one failure / six errors, seed 18085). After implementation, `bin/rails test` passed all 20 tests / 159 assertions (seed 41457). Tests cover one and three IDs, order and repeated-ID storage, absent lists, malformed lists, missing transactions and unchanged older records after successful or failed creation. The existing 13 field and validation tests still pass.
- The local migration, `bin/rails zeitwerk:check` and `git diff --check` passed. The scoped changes were reviewed, and no old association references remain in application code, migrations or tests. No CI run, commit, push or deployment was made.

### One transaction model with input references — 14 October 2026

This local step is replaced by the plain list above.

- The user approved replacing `TransactionInput` with a reference on `Transaction` itself, then narrowed this to only `has_many :inputs`. Do not add the reverse `belongs_to` association or spent-input checks.
- Add the nullable `spent_by_transaction_id` reference to `transactions`. `transaction.inputs` returns previous transactions whose reference points to it. This column holds one reference; reassignment is not prevented in this step.
- Keep the older transaction records. Keep the creation checks for at least one saved input, public-key presence and supplied numeric values. An unsaved transaction cannot be used as an input, including a new transaction referring to itself.
- Replace the earlier input model and its model-specific tests. Retain the behavior checks using the new relation. No check for spent status, replacement or clearing of a reference is added.
- The user proposed that prior blockchain inclusion means an input is spent. That remains an unverified learning assumption, not a rule implemented by this association. Blockchain and spent-status rules are outside this step.
- Counts and totals remain supplied values. The ownership and signature methods remain the user's `true` placeholders. Separate outputs and the first transaction remain later learning steps.
- Baseline: all 23 tests / 160 assertions passed (seed 44240). Both local input tables contained zero records. The development database contained zero transactions; the test database contained two fixture transactions. The empty, uncommitted input-table migration was rolled back in both databases and replaced with the reference-column migration. No transaction records were deleted.
- Before implementation, the seven association tests failed on the missing reference column and the old validation messages (two failures / five errors, seed 38467). After implementation, `bin/rails test` passed all 20 tests / 130 assertions (seed 13785). Coverage includes one or several saved inputs, input IDs, missing IDs, absent inputs, unsaved inputs and unchanged references after failed creation. The 13 existing field and validation tests still pass.
- The local migration, `bin/rails zeitwerk:check` and `git diff --check` passed. The scoped changes were reviewed. No CI run, commit, push or deployment was made. Spent-status and concurrency rules were not implemented or tested.

### References to previous transactions — 14 October 2026

This local step is replaced by the single-model relation above.

- The user now asks for one or more inputs per transaction. Each input references a previous, saved transaction. This replaces the earlier decision to defer links.
- Add `TransactionInput` with `transaction_id` for the new transaction and `previous_transaction_id` for its input. Both references are required. Rails reserves the method name `transaction`, so the input's owning association is named `parent_transaction`.
- Expose the previous transactions through `transaction.inputs`. Read their public keys and values from the referenced records; do not copy those fields onto the input records.
- Require at least one input when creating a transaction. Reject missing or unsaved previous transactions and references to the parent transaction itself.
- This step only adds the references. Input counts and totals remain supplied values. The ownership and signature methods still return `true`. Outputs, spending rules and cryptographic verification remain later steps.
- Tests use records that were already stored. The rule for creating the first transaction remains undefined; this step adds no first-transaction exception.
- Baseline before this step: all 13 tests / 96 assertions passed (seed 16905). The expanded tests then reported the expected missing model and input associations (23 errors, seed 23976).
- After implementation, `bin/rails test` passed all 23 tests / 160 assertions (seed 33677). Tests cover one and several inputs, creation through both associations, references supplied by ID, missing references, missing parents, unsaved previous transactions and self-reference. Existing field and validation tests still pass with valid input references.
- `bin/rails db:migrate`, `bin/rails zeitwerk:check` and `git diff --check` passed. The scoped diff was reviewed. No CI run, commit, push or deployment was made.

### Field names and requested validation — 14 October 2026

- Rename `receiver_public_key` to `public_key` and `sender_digital_signature` to `digital_signature`, preserving existing values.
- Add `receiver_output_value` as a decimal BTC amount with eight decimal places, matching `total_input_value`.
- The user confirmed the value rule as `total_input_value >= receiver_output_value`. Enforce it when creating a transaction. Both values must be present, numeric and finite so the comparison is meaningful. Additional payment rules remain deferred.
- The user explicitly asked for no input links and initially requested empty methods. Both ownership and signature methods now return `true`, as requested in a follow-up. They remain placeholders and do not enforce ownership or verify signatures.
- A further request adds public-key presence validation on creation. Reject missing, empty and whitespace-only keys with `Public key can't be blank`. Key format and cryptographic validity remain unchecked. The new rejection test failed before implementation (seed 8222). After implementation, all 13 tests / 96 assertions passed (seed 59921), including valid creation, all three blank-key cases and creation-only scope. The scoped diff and whitespace checks passed. No CI run, commit or push was made.
- Existing records can still be updated. These checks run on creation, as requested. The previous test that allowed creation without input totals is replaced by a check that rejects missing amounts; `input_count` remains optional.
- The field rename and receiver-value storage checks passed six tests / 21 assertions (seed 51106). The new validation tests then produced four expected failures (seed 25068). After implementation, `bin/rails test` passed all 11 tests / 82 assertions (seed 50712).
- Coverage includes saving valid amounts, rejection without saving when the receiver value is too high, all 16 pairs of values from zero through three hundred-millionths of a BTC, missing/blank/non-numeric values, and NaN/positive infinity/negative infinity for each amount. These checks cover the stated examples and finite range; they do not prove behavior for every numeric value. Creation-only behavior and the retained key/signature storage checks also pass. Ownership and signature verification remain deferred.
- The local database migration, `bin/rails zeitwerk:check` and whitespace check passed. The scoped diff was reviewed. No CI run, commit, push or deployment was made for this step.
- After changing both placeholder methods to return `true`, all 11 tests / 82 assertions still passed (seed 40201). Whitespace checks passed.

### Input count and total value — 14 October 2026

- Add `input_count` as an integer and `total_input_value` as a decimal BTC amount with eight decimal places.
- Both fields are set directly for now. They remain blank until supplied; they are not calculated from linked inputs.
- Input records, transaction links and validation rules remain deferred.
- Verification: the two new tests first failed because the fields were missing; the three existing tests still passed (seed 47299). After implementation, `bin/rails test` passed all five tests and 18 assertions (seed 12327). The examples cover ten inputs, a fractional total, zero, a one-hundred-millionth BTC amount and omitted values. These are storage checks, not payment validation or arithmetic checks. The local migration, `bin/rails zeitwerk:check` and whitespace check passed. No CI run or deployment was made.

### Transaction fields — 14 October 2026

- Start with the existing `Transaction` model and two fields: `receiver_public_key` and `sender_digital_signature`.
- The user's current proposal is to identify the receiver with a public key and use the sender's signature to authorize spending. The user wants to explore connections between transactions after defining this base model.
- The user's working idea is that inputs and outputs can be represented as connections to other transactions. This relationship design is not yet implemented or checked.
- Store both fields as text. Key and signature formats, required-field rules, signing and signature verification are deferred. Stored text alone does not establish ownership or permission to spend.
- Inputs, outputs, fees and links between transactions are deferred. Remove the previous uncommitted input model, association, tests and migration. Both local input tables were empty before removal.
- Keep the existing optional block reference. This step does not change block behavior.
- Verification: the previous input tests passed before removal (four tests / eight assertions, seed 638). The three new tests first failed on the missing fields (seed 5515). After implementation, `bin/rails test` passed all three tests and ten assertions (seed 14994). Both fields survive saving and loading, work with the existing optional block reference, and can be updated independently. The local database migration, `bin/rails zeitwerk:check` and whitespace check passed. No cryptographic checks, CI run or deployment were made for this local step.

### Previous transaction input model — 14 October 2026

This step was completed locally, then replaced by the transaction-fields step above at the user's request. It was not committed or published.

- Start with `TransactionInput` only. The user narrowed this step before implementation; fees and outputs will wait.
- A `Transaction` has many `transaction_inputs`. Each input belongs to one transaction through `transaction_id`.
- The input's Ruby association is named `parent_transaction` because Rails reserves `transaction` as a method name.
- An input has only that reference and the standard timestamps for now. Other input fields and payment rules will be added in later steps.
- Keep the existing optional block reference. This step adds no block or node behavior.
- Tests cover the saved parent reference, multiple inputs, separate transactions, saving a new transaction with an input, and a missing parent reference.
- Verification: the four tests first failed because the model and association were missing (seed 53995). After implementation, `bin/rails test` passed all four tests and eight assertions (seed 43377). The local database migration, `bin/rails zeitwerk:check` and whitespace check passed. These checks verify model storage and associations; payment rules are not implemented or tested. No CI run or deployment was made for this local step.

[Back to the README](../README.md)
