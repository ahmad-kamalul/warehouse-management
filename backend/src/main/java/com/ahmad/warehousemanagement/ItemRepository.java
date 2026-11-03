package com.ahmad.warehousemanagement;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import java.util.Optional;
import java.util.UUID;

interface ItemRepository extends JpaRepository<Item, UUID>, JpaSpecificationExecutor<Item> {
    // Ownership is part of the query, not an optional check in the frontend.
    Optional<Item> findByIdAndOwnerId(UUID id, UUID ownerId);

    java.util.List<Item> findAllByOwnerIdOrderBySkuAsc(UUID ownerId);

    @org.springframework.data.jpa.repository.Lock(jakarta.persistence.LockModeType.PESSIMISTIC_WRITE)
    @org.springframework.data.jpa.repository.Query("select i from Item i where i.id = :id and i.ownerId = :ownerId")
    Optional<Item> lockOwned(UUID id, UUID ownerId);
}
