CREATE TABLE backup_tx_userinfo AS SELECT * FROM tx_userinfo;
ALTER TABLE tx_userinfo ADD rate INT NULL;
ALTER TABLE tx_userinfo ADD rateCurrencyCode VARCHAR(3) NULL;
