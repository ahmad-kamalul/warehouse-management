package com.ahmad.warehousemanagement;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import java.util.Optional;
import java.util.UUID;

interface ItemRepository extends JpaRepository<Item, UUID>, JpaSpecificationExecutor<Item> {
    // Ownership is part of the query, not an optional check in the frontend.
    Optional<Item> findByIdAndOwnerId(UUID id, UUID ownerId);
}
