CREATE TABLE address_userinfo (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    address text NOT NULL,
    taxCategory int NOT NULL
);

CREATE UNIQUE INDEX address_userinfo_address ON address_userinfo (address);
