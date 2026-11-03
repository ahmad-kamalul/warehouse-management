package com.ahmad.warehousemanagement;

import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import java.time.Instant;
import java.util.*;

@Service
class OperationsService {
    record Master(Instant downloadedAt, List<ApiModels.ItemView> items) {}
    record Input(@NotNull UUID clientId, @NotNull UUID itemId,
        @NotNull Type type, @NotNull @Min(0) Integer quantity,
        @PositiveOrZero Long expectedVersion,
        @NotBlank @Size(max = 100) String reference,
        @NotNull @Size(max = 2000) String notes) {}
    enum Type { STOCK_COUNT, GOODS_IN, GOODS_OUT }
    record Receipt(UUID id, UUID clientId, UUID itemId, String sku, String type,
        int quantity, String reference, String notes, int beforeQuantity,
        int afterQuantity, long appliedVersion, Instant uploadedAt) {}

    private final ItemRepository items;
    private final UserRepository users;
    private final InventoryTransactionRepository transactions;
    OperationsService(ItemRepository items, UserRepository users, InventoryTransactionRepository transactions) {
        this.items = items; this.users = users; this.transactions = transactions;
    }

    @Transactional(readOnly = true)
    public Master master(UUID owner) {
        // One SQL read prevents page drift during a master download.
        return new Master(Instant.now(), items.findAllByOwnerIdOrderBySkuAsc(owner)
            .stream().map(ItemService::view).toList());
    }

    @Transactional
    public Receipt upload(UUID owner, Input input) {
        // Serialize requests for this account, including simultaneous retries of a new ID.
        users.lockById(owner).orElseThrow(() -> error(HttpStatus.UNAUTHORIZED, "Account not found"));
        var previous = transactions.findByOwnerIdAndClientId(owner, input.clientId());
        if (previous.isPresent()) {
            InventoryTransaction p = previous.get();
            if (!p.itemId.equals(input.itemId()) || !p.type.equals(input.type().name()) ||
                p.quantity != input.quantity() || !Objects.equals(p.expectedVersion, input.expectedVersion()) ||
                !p.reference.equals(input.reference().trim()) || !p.notes.equals(input.notes().trim())) {
                throw error(HttpStatus.CONFLICT, "This transaction ID was already used with different content");
            }
            return receipt(p);
        }
        Item item = items.lockOwned(input.itemId(), owner)
            .orElseThrow(() -> error(HttpStatus.NOT_FOUND, "Item not found"));
        if (input.type() == Type.STOCK_COUNT && (input.expectedVersion() == null ||
            input.expectedVersion() != item.version)) {
            throw error(HttpStatus.CONFLICT, "Stock changed after download. Download master and recount this item.");
        }
        if (input.type() != Type.STOCK_COUNT && input.quantity() == 0) {
            throw error(HttpStatus.BAD_REQUEST, "Goods movement quantity must be greater than zero");
        }
        int before = item.quantity;
        long after = switch (input.type()) {
            case STOCK_COUNT -> input.quantity();
            case GOODS_IN -> (long) before + input.quantity();
            case GOODS_OUT -> (long) before - input.quantity();
        };
        if (after < 0) throw error(HttpStatus.CONFLICT, "Insufficient stock for goods out");
        if (after > Integer.MAX_VALUE) throw error(HttpStatus.BAD_REQUEST, "Stock quantity exceeds supported limit");
        item.quantity = (int) after;
        items.flush();
        InventoryTransaction t = new InventoryTransaction();
        t.id = UUID.randomUUID(); t.ownerId = owner; t.clientId = input.clientId();
        t.itemId = item.id; t.sku = item.sku; t.type = input.type().name();
        t.quantity = input.quantity(); t.expectedVersion = input.expectedVersion();
        t.reference = input.reference().trim(); t.notes = input.notes().trim();
        t.beforeQuantity = before; t.afterQuantity = item.quantity;
        // Match SQL timestamp precision so the initial receipt and every replay are identical.
        t.appliedVersion = item.version;
        t.uploadedAt = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        transactions.saveAndFlush(t);
        return receipt(t);
    }

    @Transactional(readOnly = true)
    public List<Receipt> history(UUID owner) {
        return transactions.findByOwnerIdOrderByUploadedAtDesc(owner,
            org.springframework.data.domain.PageRequest.of(0, 100)).stream().map(OperationsService::receipt).toList();
    }
    private static Receipt receipt(InventoryTransaction t) {
        return new Receipt(t.id, t.clientId, t.itemId, t.sku, t.type, t.quantity,
            t.reference, t.notes, t.beforeQuantity, t.afterQuantity, t.appliedVersion, t.uploadedAt);
    }
    private static ResponseStatusException error(HttpStatus status, String message) {
        return new ResponseStatusException(status, message);
    }
}
