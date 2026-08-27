CREATE TABLE tx_userinfo (
    txHash BLOB PRIMARY KEY,
    taxCategory int
);

CREATE UNIQUE INDEX idx_tx_userinfo_hash ON tx_userinfo (txHash);
