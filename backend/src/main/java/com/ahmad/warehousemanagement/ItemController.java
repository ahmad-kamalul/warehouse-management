package com.ahmad.warehousemanagement;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import java.net.URI;
import java.util.UUID;
import static com.ahmad.warehousemanagement.ApiModels.*;

@RestController
@RequestMapping("/api/items")
@Validated
class ItemController {
    private final ItemService service;
    ItemController(ItemService service) { this.service = service; }

    @GetMapping
    ItemPage list(@AuthenticationPrincipal Jwt jwt,
                  @RequestParam(defaultValue = "") @Size(max = 100) String q,
                  @RequestParam(defaultValue = "") @Size(max = 80) String category,
                  @RequestParam(defaultValue = "false") boolean lowStock,
                  @RequestParam(defaultValue = "0") @Min(0) int page,
                  @RequestParam(defaultValue = "10") @Min(1) @Max(100) int size,
                  @RequestParam(defaultValue = "updatedAt") String sortBy,
                  @RequestParam(defaultValue = "desc") String direction) {
        return service.list(owner(jwt), q, category, lowStock, page, size, sortBy, direction);
    }

    @GetMapping("/{id}")
    ItemView get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return service.get(owner(jwt), id);
    }

    @PostMapping
    ResponseEntity<ItemView> create(@AuthenticationPrincipal Jwt jwt,
                                     @Valid @RequestBody ItemInput input) {
        ItemView result = service.create(owner(jwt), input);
        return ResponseEntity.created(URI.create("/api/items/" + result.id())).body(result);
    }

    @PutMapping("/{id}")
    ItemView update(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id,
                    @Valid @RequestBody ItemInput input) {
        return service.update(owner(jwt), id, input);
    }

    @DeleteMapping("/{id}")
    ResponseEntity<Void> delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        service.delete(owner(jwt), id);
        return ResponseEntity.noContent().build();
    }

    private static UUID owner(Jwt jwt) { return UUID.fromString(jwt.getSubject()); }
}
