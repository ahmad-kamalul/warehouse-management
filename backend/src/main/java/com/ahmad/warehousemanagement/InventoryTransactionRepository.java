package com.ahmad.warehousemanagement;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.domain.Pageable;
import java.util.*;

interface InventoryTransactionRepository extends JpaRepository<InventoryTransaction, UUID> {
    Optional<InventoryTransaction> findByOwnerIdAndClientId(UUID ownerId, UUID clientId);
    List<InventoryTransaction> findByOwnerIdOrderByUploadedAtDesc(UUID ownerId, Pageable pageable);
}
