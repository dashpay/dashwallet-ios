-- Adding metadata fields to tx_userinfo table
ALTER TABLE tx_userinfo ADD timestamp BIGINT NULL;
ALTER TABLE tx_userinfo ADD memo TEXT NULL;
ALTER TABLE tx_userinfo ADD service TEXT NULL;
ALTER TABLE tx_userinfo ADD customIconId BLOB NULL; 