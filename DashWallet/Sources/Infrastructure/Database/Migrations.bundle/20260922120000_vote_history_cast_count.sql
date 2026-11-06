-- How many times this device has cast a vote with one node on one contest.
--
-- The table keeps a single row per (node, contest, network) — the vote that
-- node currently holds — because that is what the UI asks for. Platform,
-- however, limits a masternode to five casts per contest in total
-- (`votes_allowed_per_masternode`), and a row count can never reach five: a
-- change overwrites the row it came from.
--
-- Existing rows represent at least one cast, hence the default.
ALTER TABLE masternode_vote_history
    ADD COLUMN castCount INTEGER NOT NULL DEFAULT 1;
