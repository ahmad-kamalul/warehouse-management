package com.ahmad.warehousemanagement;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "items")
class Item {
    @Id @GeneratedValue(strategy = GenerationType.UUID)
    UUID id;
    @Column(name = "owner_id", nullable = false, updatable = false)
    UUID ownerId;
    @Column(nullable = false, length = 120)
    String name;
    @Column(nullable = false, length = 40)
    String sku;
    @Column(nullable = false, length = 80)
    String category;
    @Column(nullable = false)
    int quantity;
    @Column(name = "reorder_level", nullable = false)
    int reorderLevel;
    @Column(nullable = false, precision = 12, scale = 2)
    BigDecimal price;
    @Column(length = 2000)
    String notes;
    // Hibernate checks this in UPDATE/DELETE SQL to detect concurrent writes.
    @Version @Column(nullable = false)
    long version;
    @Column(name = "created_at", nullable = false, updatable = false)
    Instant createdAt;
    @Column(name = "updated_at", nullable = false)
    Instant updatedAt;

    protected Item() {}

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }
}
