# Bitcoin from Paper

A Ruby on Rails implementation of the ideas in the Bitcoin whitepaper, built incrementally from the paper and early mailing-list and forum discussions.

The goal is a working prototype whose parts fit together: transactions, blocks, proof of work, peer communication, and agreement on a transaction history. We prioritize understandable code and correct behavior over performance.

## Approach

- Build in small, agreed steps, discussing each part before implementing it.
- Use the whitepaper and early discussions as references, without reading or reusing Bitcoin implementation source code.
- Make our own implementation choices explicit where the references leave details open.
- Verify meaningful behavior as the prototype grows.

Compatibility with the existing Bitcoin network is not currently a goal.

## Current state

The initial data model contains two models:

- `Block` has many transactions.
- `Transaction` optionally belongs to a block, allowing it to exist before inclusion in a block.

This is a starting point, not yet a functioning cryptocurrency. Transaction inputs, outputs, and networking are left for later steps. The association currently allows a transaction to belong to only one block; handling competing branches will require revisiting it.

## Run locally

Use Ruby 3.4.5 (see `.ruby-version`). The app uses Rails 8.1 and SQLite.

```sh
git clone https://github.com/arjunrajkumar/bitcoin-from-paper.git
cd bitcoin-from-paper
bundle install
bin/rails db:prepare
bin/rails console
```

Try the relationship in the Rails console:

```ruby
transaction = Transaction.create!
transaction.block # => nil

block = Block.create!
block.transactions << transaction
transaction.reload.block == block # => true
```

Run `bin/rails server` to start the app. There are no application screens or API endpoints yet.

## References

- [Bitcoin: A Peer-to-Peer Electronic Cash System](https://bitcoin.org/bitcoin.pdf)
- [Early cryptography mailing-list discussion](https://satoshi.nakamotoinstitute.org/emails/cryptography/17/)
