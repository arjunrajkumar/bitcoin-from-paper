CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "blocks" ("id" varchar(64) NOT NULL PRIMARY KEY, "height" integer NOT NULL, "header" json DEFAULT '{"transactions_hash":null,"created_at":null,"previous_header_hash":null}' NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT block_height_nonnegative CHECK (height >= 0)) WITHOUT ROWID;
CREATE UNIQUE INDEX "index_blocks_on_height" ON "blocks" ("height");
CREATE TABLE IF NOT EXISTS "transactions" ("id" varchar(64) NOT NULL PRIMARY KEY, "public_key" text, "digital_signature" text, "input_count" integer, "receiver_output_value" varchar, "input_transaction_ids" json DEFAULT '[]', "block_id" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_12379b5f88"
FOREIGN KEY ("block_id")
  REFERENCES "blocks" ("id")
) WITHOUT ROWID;
CREATE INDEX "index_transactions_on_block_id" ON "transactions" ("block_id");
CREATE TABLE IF NOT EXISTS "candidate_blocks" ("id" varchar(64) NOT NULL PRIMARY KEY, "identity_seed" varchar(64) NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS "nodes" ("id" varchar(64) NOT NULL PRIMARY KEY, "identity_seed" varchar(64) NOT NULL, "candidate_block_id" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_e760102710"
FOREIGN KEY ("candidate_block_id")
  REFERENCES "candidate_blocks" ("id")
) WITHOUT ROWID;
CREATE INDEX "index_nodes_on_candidate_block_id" ON "nodes" ("candidate_block_id");
CREATE TRIGGER transactions_immutable_content
BEFORE UPDATE ON transactions
WHEN OLD.id IS NOT NEW.id OR OLD.input_transaction_ids IS NOT NEW.input_transaction_ids OR OLD.input_count IS NOT NEW.input_count OR OLD.receiver_output_value IS NOT NEW.receiver_output_value OR OLD.public_key IS NOT NEW.public_key OR OLD.digital_signature IS NOT NEW.digital_signature
BEGIN
  SELECT RAISE(ABORT, 'Transaction content cannot change after creation');
END;
CREATE TRIGGER transactions_hash_format
BEFORE INSERT ON transactions
WHEN length(NEW.id) != 64 OR NEW.id GLOB '*[^0-9a-f]*'
BEGIN
  SELECT RAISE(ABORT, 'Transaction id must be a lowercase 64-character hash');
END;
CREATE TRIGGER blocks_immutable_content
BEFORE UPDATE ON blocks
WHEN OLD.id IS NOT NEW.id OR OLD.header IS NOT NEW.header OR OLD.height IS NOT NEW.height
BEGIN
  SELECT RAISE(ABORT, 'Block content cannot change after creation');
END;
CREATE TRIGGER blocks_hash_format
BEFORE INSERT ON blocks
WHEN length(NEW.id) != 64 OR NEW.id GLOB '*[^0-9a-f]*'
BEGIN
  SELECT RAISE(ABORT, 'Block id must be a lowercase 64-character hash');
END;
CREATE TRIGGER nodes_immutable_content
BEFORE UPDATE ON nodes
WHEN OLD.id IS NOT NEW.id OR OLD.identity_seed IS NOT NEW.identity_seed
BEGIN
  SELECT RAISE(ABORT, 'Node content cannot change after creation');
END;
CREATE TRIGGER nodes_hash_format
BEFORE INSERT ON nodes
WHEN length(NEW.id) != 64 OR NEW.id GLOB '*[^0-9a-f]*'
BEGIN
  SELECT RAISE(ABORT, 'Node id must be a lowercase 64-character hash');
END;
CREATE TRIGGER candidate_blocks_immutable_content
BEFORE UPDATE ON candidate_blocks
WHEN OLD.id IS NOT NEW.id OR OLD.identity_seed IS NOT NEW.identity_seed
BEGIN
  SELECT RAISE(ABORT, 'CandidateBlock content cannot change after creation');
END;
CREATE TRIGGER candidate_blocks_hash_format
BEFORE INSERT ON candidate_blocks
WHEN length(NEW.id) != 64 OR NEW.id GLOB '*[^0-9a-f]*'
BEGIN
  SELECT RAISE(ABORT, 'CandidateBlock id must be a lowercase 64-character hash');
END;
INSERT INTO "schema_migrations" (version) VALUES
('20261015000016'),
('20261015000015'),
('20261015000014'),
('20261015000013'),
('20261015000012'),
('20261014000011'),
('20261014000010'),
('20261014000009'),
('20261014000008'),
('20261014000007'),
('20261014000006'),
('20261014000005'),
('20261014000004'),
('20261014000003'),
('20261014000002'),
('20261012000002'),
('20261012000001');
