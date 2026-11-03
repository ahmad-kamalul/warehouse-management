package com.ahmad.warehousemanagement;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "inventory_transactions")
class InventoryTransaction {
    @Id UUID id;
    @Column(name = "owner_id", nullable = false) UUID ownerId;
    @Column(name = "client_id", nullable = false) UUID clientId;
    @Column(name = "item_id", nullable = false) UUID itemId;
    @Column(nullable = false, length = 40) String sku;
    @Column(nullable = false, length = 20) String type;
    @Column(nullable = false) int quantity;
    @Column(name = "expected_version") Long expectedVersion;
    @Column(nullable = false, length = 100) String reference;
    @Column(nullable = false, length = 2000) String notes;
    @Column(name = "before_quantity", nullable = false) int beforeQuantity;
    @Column(name = "after_quantity", nullable = false) int afterQuantity;
    @Column(name = "applied_version", nullable = false) long appliedVersion;
    @Column(name = "uploaded_at", nullable = false) Instant uploadedAt;
}
