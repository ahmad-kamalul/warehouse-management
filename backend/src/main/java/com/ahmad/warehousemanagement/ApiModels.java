package com.ahmad.warehousemanagement;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Immutable API DTOs. Entities and password hashes never leave the backend. */
public final class ApiModels {
    private ApiModels() {}

    public record RegisterRequest(
            @NotBlank @Size(max = 100) String name,
            @NotBlank @Email @Size(max = 254) String email,
            @NotBlank @Size(min = 12, max = 72) String password) {}

    public record LoginRequest(
            @NotBlank @Email @Size(max = 254) String email,
            @NotBlank @Size(max = 72) String password) {}

    public record UserView(UUID id, String name, String email) {}
    public record AuthResponse(String accessToken, String tokenType,
                               long expiresIn, UserView user) {}

    /** Version is optional on creation, required by the service on updates. */
    public record ItemInput(
            @NotBlank @Size(max = 120) String name,
            @NotBlank @Pattern(regexp = "[A-Za-z0-9_-]{1,40}") String sku,
            @NotBlank @Size(max = 80) String category,
            @NotNull @Min(0) Integer quantity,
            @NotNull @Min(0) Integer reorderLevel,
            @NotNull @DecimalMin("0.00") @Digits(integer = 10, fraction = 2) BigDecimal price,
            @Size(max = 2000) String notes,
            @PositiveOrZero Long version) {}

    public record ItemView(UUID id, String name, String sku, String category,
                           int quantity, int reorderLevel, BigDecimal price,
                           String notes, long version, Instant createdAt,
                           Instant updatedAt, boolean lowStock) {}

    /** Stable pagination contract independent of Spring's Page serialization. */
    public record ItemPage(List<ItemView> content, long totalElements,
                           int totalPages, int page, int size) {}

    public record ApiError(Instant timestamp, int status, String message,
                           Map<String, String> errors) {}
}
