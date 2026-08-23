-- One row per (masternode, contest, network): the vote this device last cast
-- with that node on that contest.
--
-- Needed so the voting UI can say how many of your nodes have already voted on
-- a contest, and so "vote with one node at a time" knows which node is next.
-- Platform can be asked who voted, but only per contender and only by voter
-- identity, so answering "which of MY nodes voted here" from the network costs
-- a query per contender and still cannot see abstain/lock voters.
--
-- `proTxHash` is stored in raw wire byte order, matching PlatformMasternode.
-- `castAt` is milliseconds since epoch.
CREATE TABLE masternode_vote_history (
    proTxHash BLOB NOT NULL,
    normalizedLabel TEXT NOT NULL,
    network TEXT NOT NULL,
    choice TEXT NOT NULL,
    contenderIdentityId TEXT,
    castAt INTEGER NOT NULL,
    PRIMARY KEY (proTxHash, normalizedLabel, network)
);

CREATE INDEX idx_masternode_vote_history_contest
    ON masternode_vote_history (normalizedLabel, network);
