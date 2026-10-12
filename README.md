# Bitcoin from Paper

I'm looking to build Bitcoin, without looking at the source code of Bitcoin. So, I'll build it out by looking at the Bitcoin paper, the early forum posts, the cryptography mailing list posts, and by chatting with GPT-6 Astra.

The goal is to get a deep understanding of how Bitcoin works. By first build it out using my solutions, then finding the errors and improving it by looking at the actual Bitcoin code.

<a href="https://github.com/arjunrajkumar/bitcoin-from-paper"><ins>GitHub</ins></a>

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
