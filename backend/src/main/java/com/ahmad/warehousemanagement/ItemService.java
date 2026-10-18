package com.ahmad.warehousemanagement;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.*;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import static com.ahmad.warehousemanagement.ApiModels.*;

@Service
class ItemService {
    private static final Logger log = LoggerFactory.getLogger(ItemService.class);
    private static final Set<String> SORT_FIELDS = Set.of("name", "sku", "quantity", "price", "updatedAt");
    private final ItemRepository items;
    ItemService(ItemRepository items) { this.items = items; }

    @Transactional(readOnly = true)
    public ItemPage list(UUID ownerId, String query, String category, boolean lowStock,
                         int page, int size, String sortBy, String direction) {
        // Do not expose arbitrary entity property names through client sorting.
        if (!SORT_FIELDS.contains(sortBy)) throw badRequest("Unsupported sort field");
        Sort.Direction order = switch (direction.toLowerCase(Locale.ROOT)) {
            case "asc" -> Sort.Direction.ASC;
            case "desc" -> Sort.Direction.DESC;
            default -> throw badRequest("Direction must be asc or desc");
        };
        Specification<Item> specification = (root, criteria, builder) ->
                builder.equal(root.get("ownerId"), ownerId);
        if (query != null && !query.isBlank()) {
            String pattern = "%" + escapeLike(query.trim().toLowerCase(Locale.ROOT)) + "%";
            specification = specification.and((root, criteria, builder) -> builder.or(
                    builder.like(builder.lower(root.<String>get("name")), pattern, '!'),
                    builder.like(builder.lower(root.<String>get("sku")), pattern, '!'),
                    builder.like(builder.lower(root.<String>get("category")), pattern, '!')));
        }
        if (category != null && !category.isBlank()) {
            String normalized = category.trim().toLowerCase(Locale.ROOT);
            specification = specification.and((root, criteria, builder) ->
                    builder.equal(builder.lower(root.<String>get("category")), normalized));
        }
        if (lowStock) {
            specification = specification.and((root, criteria, builder) ->
                    builder.lessThanOrEqualTo(root.<Integer>get("quantity"), root.<Integer>get("reorderLevel")));
        }
        // Stable ID tie-breaker when rows share the same sort value.
        Sort sort = Sort.by(order, sortBy).and(Sort.by(Sort.Direction.ASC, "id"));
        Page<Item> result = items.findAll(specification, PageRequest.of(page, size, sort));
        return new ItemPage(result.getContent().stream().map(ItemService::view).toList(),
                result.getTotalElements(), result.getTotalPages(), result.getNumber(), result.getSize());
    }

    @Transactional(readOnly = true)
    public ItemView get(UUID ownerId, UUID itemId) { return view(findOwned(ownerId, itemId)); }

    @Transactional
    public ItemView create(UUID ownerId, ItemInput input) {
        Item item = new Item();
        // The verified JWT supplies ownership, never client JSON.
        item.ownerId = ownerId;
        apply(item, input);
        items.saveAndFlush(item);
        log.info("User {} created item {}", ownerId, item.id);
        return view(item);
    }

    @Transactional
    public ItemView update(UUID ownerId, UUID itemId, ItemInput input) {
        Item item = findOwned(ownerId, itemId);
        if (input.version() == null) throw badRequest("Version is required when updating");
        if (input.version().longValue() != item.version) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Item changed. Reopen it before saving again.");
        }
        apply(item, input);
        // Surface uniqueness/optimistic-lock failures before returning the DTO.
        items.flush();
        log.info("User {} updated item {}", ownerId, item.id);
        return view(item);
    }

    @Transactional
    public void delete(UUID ownerId, UUID itemId) {
        Item item = findOwned(ownerId, itemId);
        items.delete(item);
        items.flush();
        log.info("User {} deleted item {}", ownerId, itemId);
    }

    private Item findOwned(UUID ownerId, UUID itemId) {
        return items.findByIdAndOwnerId(itemId, ownerId).orElseThrow(() ->
                new ResponseStatusException(HttpStatus.NOT_FOUND, "Item not found"));
    }

    private static void apply(Item item, ItemInput input) {
        item.name = input.name().trim();
        item.sku = input.sku().trim().toUpperCase(Locale.ROOT);
        item.category = input.category().trim();
        item.quantity = input.quantity();
        item.reorderLevel = input.reorderLevel();
        item.price = input.price();
        item.notes = input.notes() == null ? "" : input.notes().trim();
    }

    private static ItemView view(Item item) {
        return new ItemView(item.id, item.name, item.sku, item.category, item.quantity,
                item.reorderLevel, item.price, item.notes, item.version,
                item.createdAt, item.updatedAt, item.quantity <= item.reorderLevel);
    }

    private static String escapeLike(String text) {
        // Search '%'/'_' as literal text, not SQL LIKE wildcard operators.
        return text.replace("!", "!!").replace("%", "!%").replace("_", "!_");
    }

    private static ResponseStatusException badRequest(String message) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, message);
    }
}
