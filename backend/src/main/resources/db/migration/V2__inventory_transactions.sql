-- Immutable movement receipts. item_id deliberately has no FK: audit survives deletion.
CREATE TABLE inventory_transactions (
    id UUID PRIMARY KEY,
    owner_id UUID NOT NULL REFERENCES app_users(id),
    client_id UUID NOT NULL,
    item_id UUID NOT NULL,
    sku VARCHAR(40) NOT NULL,
    type VARCHAR(20) NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity >= 0),
    expected_version BIGINT,
    reference VARCHAR(100) NOT NULL,
    notes VARCHAR(2000) NOT NULL,
    before_quantity INTEGER NOT NULL CHECK (before_quantity >= 0),
    after_quantity INTEGER NOT NULL CHECK (after_quantity >= 0),
    applied_version BIGINT NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_transactions_owner_client UNIQUE(owner_id, client_id),
    CONSTRAINT ck_transactions_type CHECK (type IN ('STOCK_COUNT', 'GOODS_IN', 'GOODS_OUT'))
);
CREATE INDEX ix_transactions_owner_uploaded ON inventory_transactions(owner_id, uploaded_at);
