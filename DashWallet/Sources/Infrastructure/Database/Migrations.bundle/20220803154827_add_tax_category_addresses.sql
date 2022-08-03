CREATE TABLE tax_category_address (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    address text NOT NULL,
    taxCategory int NOT NULL
);

CREATE UNIQUE INDEX tax_category_address_address ON tax_category_address (address);
