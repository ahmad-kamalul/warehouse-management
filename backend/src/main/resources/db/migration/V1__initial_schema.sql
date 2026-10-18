-- Flyway records the checksum. Future changes go in V2__, V3__, etc.
CREATE TABLE app_users (
    id UUID PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(254) NOT NULL,
    password_hash VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_users_email UNIQUE (email)
);
CREATE TABLE items (
    id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    name VARCHAR(120) NOT NULL,
    sku VARCHAR(40) NOT NULL,
    category VARCHAR(80) NOT NULL,
    quantity INTEGER NOT NULL,
    reorder_level INTEGER NOT NULL,
    price NUMERIC(12, 2) NOT NULL,
    notes VARCHAR(2000),
    version BIGINT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT fk_items_owner FOREIGN KEY (owner_id) REFERENCES app_users(id),
    -- SKUs are unique per user, not globally.
    CONSTRAINT uq_items_owner_sku UNIQUE (owner_id, sku),
    CONSTRAINT ck_items_quantity CHECK (quantity >= 0),
    CONSTRAINT ck_items_reorder CHECK (reorder_level >= 0),
    CONSTRAINT ck_items_price CHECK (price >= 0)
);
CREATE INDEX ix_items_owner_updated ON items(owner_id, updated_at);
