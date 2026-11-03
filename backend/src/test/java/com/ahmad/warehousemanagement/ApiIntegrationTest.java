package com.ahmad.warehousemanagement;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.*;
import org.springframework.test.context.ActiveProfiles;
import java.math.BigDecimal;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import static org.assertj.core.api.Assertions.assertThat;

/** Real HTTP integration tests through Security, controllers, services, and SQL. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class ApiIntegrationTest {
    @Autowired TestRestTemplate http;

    @Test
    void registrationLoginAndProtectedRoutes() {
        String email = uniqueEmail();
        ResponseEntity<JsonNode> registration = request(HttpMethod.POST, "/api/auth/register", null,
                Map.of("name", "Test User", "email", email, "password", "CorrectPassword123!"));
        assertThat(registration.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(registration.getBody().get("user").has("passwordHash")).isFalse();
        String token = registration.getBody().get("accessToken").asText();
        assertThat(request(HttpMethod.GET, "/api/auth/me", token, null).getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(request(HttpMethod.GET, "/api/items", null, null).getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(request(HttpMethod.GET, "/api/items", "invalid-token", null).getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(request(HttpMethod.POST, "/api/auth/login", null,
                Map.of("email", email, "password", "WrongPassword123!")).getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(request(HttpMethod.POST, "/api/auth/login", null,
                Map.of("email", email.toUpperCase(), "password", "CorrectPassword123!")).getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(request(HttpMethod.POST, "/api/auth/register", null,
                Map.of("name", "Duplicate", "email", email.toUpperCase(), "password", "CorrectPassword123!")).getStatusCode())
                .isEqualTo(HttpStatus.CONFLICT);
    }

    @Test
    void crudEnforcesOwnershipAndDetectsStaleUpdates() {
        String owner = registerUser();
        String otherUser = registerUser();
        ResponseEntity<JsonNode> creation = request(HttpMethod.POST, "/api/items", owner, item("Keyboard", "KEY-01", 3));
        assertThat(creation.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        JsonNode created = creation.getBody();
        String endpoint = "/api/items/" + created.get("id").asText();
        assertThat(request(HttpMethod.GET, endpoint, otherUser, null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        Map<String, Object> update = item("Mechanical Keyboard", "KEY-01", 8);
        update.put("version", created.get("version").asLong());
        assertThat(request(HttpMethod.PUT, endpoint, otherUser, update).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(request(HttpMethod.DELETE, endpoint, otherUser, null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(request(HttpMethod.GET, "/api/items", otherUser, null).getBody().get("totalElements").asLong()).isZero();
        ResponseEntity<JsonNode> updated = request(HttpMethod.PUT, endpoint, owner, update);
        assertThat(updated.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(updated.getBody().get("quantity").asInt()).isEqualTo(8);
        assertThat(updated.getBody().get("version").asLong()).isGreaterThan(created.get("version").asLong());
        // Original version must not overwrite the newer row.
        assertThat(request(HttpMethod.PUT, endpoint, owner, update).getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(request(HttpMethod.DELETE, endpoint, owner, null).getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        assertThat(request(HttpMethod.GET, endpoint, owner, null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void validationUniquenessAndFiltersWork() {
        String token = registerUser();
        assertThat(request(HttpMethod.POST, "/api/items", token, item("Invalid", "BAD-01", -1)).getStatusCode())
                .isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(request(HttpMethod.POST, "/api/items", token, item("Keyboard", "KEY-01", 2)).getStatusCode())
                .isEqualTo(HttpStatus.CREATED);
        assertThat(request(HttpMethod.POST, "/api/items", token, item("Monitor", "MON-01", 20)).getStatusCode())
                .isEqualTo(HttpStatus.CREATED);
        assertThat(request(HttpMethod.POST, "/api/items", token, item("Duplicate", "key-01", 4)).getStatusCode())
                .isEqualTo(HttpStatus.CONFLICT);
        JsonNode lowStock = request(HttpMethod.GET, "/api/items?lowStock=true", token, null).getBody();
        assertThat(lowStock.get("totalElements").asLong()).isEqualTo(1);
        assertThat(lowStock.get("content").get(0).get("sku").asText()).isEqualTo("KEY-01");
        JsonNode search = request(HttpMethod.GET, "/api/items?q=keyboard&category=Hardware", token, null).getBody();
        assertThat(search.get("totalElements").asLong()).isEqualTo(1);
        JsonNode sorted = request(HttpMethod.GET, "/api/items?sortBy=name&direction=asc&size=1", token, null).getBody();
        assertThat(sorted.get("totalElements").asLong()).isEqualTo(2);
        assertThat(sorted.get("totalPages").asInt()).isEqualTo(2);
        assertThat(sorted.get("content").get(0).get("name").asText()).isEqualTo("Keyboard");
        assertThat(request(HttpMethod.GET, "/api/items?sortBy=ownerId", token, null).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(request(HttpMethod.GET, "/api/items?size=101", token, null).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(request(HttpMethod.GET, "/api/items?page=-1", token, null).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    void rejectsUnknownFieldsMalformedIdsAndMissingVersion() {
        String token = registerUser();
        Map<String, Object> body = item("Mouse", "M-01", 2);
        body.put("ownerId", UUID.randomUUID().toString());
        assertThat(request(HttpMethod.POST, "/api/items", token, body).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        body.remove("ownerId");
        JsonNode created = request(HttpMethod.POST, "/api/items", token, body).getBody();
        assertThat(request(HttpMethod.PUT, "/api/items/" + created.get("id").asText(), token, body).getStatusCode())
                .isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(request(HttpMethod.GET, "/api/items/not-a-uuid", token, null).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(request(HttpMethod.GET, "/api/items?q=%25", token, null).getBody().get("totalElements").asLong()).isZero();
    }

    @Test
    void corsAllowsOnlyConfiguredFrontend() {
        HttpHeaders allowed = new HttpHeaders();
        allowed.setOrigin("http://localhost:5173");
        allowed.setAccessControlRequestMethod(HttpMethod.GET);
        ResponseEntity<String> response = http.exchange("/api/items", HttpMethod.OPTIONS,
                new HttpEntity<>(null, allowed), String.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getHeaders().getAccessControlAllowOrigin()).isEqualTo("http://localhost:5173");
        allowed.setOrigin("https://untrusted.example");
        assertThat(http.exchange("/api/items", HttpMethod.OPTIONS,
                new HttpEntity<>(null, allowed), String.class).getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void movementsAreIdempotentAuditedAndOwned() {
        String owner = registerUser();
        String other = registerUser();
        JsonNode item = request(HttpMethod.POST, "/api/items", owner, item("Box", "BOX", 10)).getBody();
        var input = movement(item, "GOODS_IN", 5);
        JsonNode receipt = request(HttpMethod.POST, "/api/operations/transactions", owner, input).getBody();
        assertThat(receipt.get("beforeQuantity").asInt()).isEqualTo(10);
        assertThat(receipt.get("afterQuantity").asInt()).isEqualTo(15);
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", owner, input).getBody())
            .isEqualTo(receipt);
        assertThat(request(HttpMethod.GET, "/api/items/" + item.get("id").asText(), owner, null)
            .getBody().get("quantity").asInt()).isEqualTo(15);
        input.put("quantity", 6);
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", owner, input).getStatusCode())
            .isEqualTo(HttpStatus.CONFLICT);
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", other, movement(item, "GOODS_OUT", 1))
            .getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(request(HttpMethod.GET, "/api/operations/master", other, null).getBody().get("items").size()).isZero();
        assertThat(request(HttpMethod.GET, "/api/operations/transactions", other, null).getBody().size()).isZero();
        assertThat(request(HttpMethod.GET, "/api/operations/transactions", owner, null).getBody().size()).isEqualTo(1);
        request(HttpMethod.DELETE, "/api/items/" + item.get("id").asText(), owner, null);
        // Receipt survives item deletion, including retrying an acknowledged ID.
        input.put("quantity", 5);
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", owner, input).getBody()).isEqualTo(receipt);
    }

    @Test
    void stockCountsUseVersionsAndGoodsOutCannotMakeStockNegative() {
        String token = registerUser();
        JsonNode item = request(HttpMethod.POST, "/api/items", token, item("Box", "BOX", 10)).getBody();
        var staleCount = movement(item, "STOCK_COUNT", 7);
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", token,
            movement(item, "GOODS_OUT", 11)).getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(request(HttpMethod.GET, "/api/operations/transactions", token, null).getBody().size()).isZero();
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", token,
            movement(item, "GOODS_OUT", 3)).getBody().get("afterQuantity").asInt()).isEqualTo(7);
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", token, staleCount)
            .getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        JsonNode fresh = request(HttpMethod.GET, "/api/items/" + item.get("id").asText(), token, null).getBody();
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", token,
            movement(fresh, "STOCK_COUNT", 0)).getBody().get("afterQuantity").asInt()).isZero();
        JsonNode master = request(HttpMethod.GET, "/api/operations/master", token, null).getBody();
        assertThat(master.get("items").size()).isEqualTo(1);
        assertThat(master.get("items").get(0).get("quantity").asInt()).isZero();
        assertThat(request(HttpMethod.GET, "/api/operations/master", null, null).getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void movementsRejectZeroNegativeOverflowAndMissingCountVersion() {
        String token = registerUser();
        JsonNode item = request(HttpMethod.POST, "/api/items", token,
            item("Box", "BOX", Integer.MAX_VALUE)).getBody();
        for (int quantity : new int[]{0, -1, 1}) {
            assertThat(request(HttpMethod.POST, "/api/operations/transactions", token,
                movement(item, "GOODS_IN", quantity)).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }
        var missingVersion = movement(item, "STOCK_COUNT", 4);
        var fractional = movement(item, "GOODS_OUT", 1);
        fractional.put("quantity", 1.5);
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", token, fractional)
            .getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        missingVersion.remove("expectedVersion");
        assertThat(request(HttpMethod.POST, "/api/operations/transactions", token, missingVersion)
            .getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(request(HttpMethod.GET, "/api/items/" + item.get("id").asText(), token, null)
            .getBody().get("quantity").asInt()).isEqualTo(Integer.MAX_VALUE);
    }

    @Test
    void simultaneousRetriesApplyTheSameMovementOnce() throws Exception {
        String token = registerUser();
        JsonNode item = request(HttpMethod.POST, "/api/items", token, item("Box", "BOX", 10)).getBody();
        var input = movement(item, "GOODS_IN", 5);
        try (var executor = java.util.concurrent.Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> request(HttpMethod.POST, "/api/operations/transactions", token, input));
            var second = executor.submit(() -> request(HttpMethod.POST, "/api/operations/transactions", token, input));
            var a = first.get(15, java.util.concurrent.TimeUnit.SECONDS);
            var b = second.get(15, java.util.concurrent.TimeUnit.SECONDS);
            assertThat(a.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(b.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(a.getBody()).isEqualTo(b.getBody());
        }
        assertThat(request(HttpMethod.GET, "/api/items/" + item.get("id").asText(), token, null)
            .getBody().get("quantity").asInt()).isEqualTo(15);
    }

    private static Map<String, Object> movement(JsonNode item, String type, int quantity) {
        Map<String, Object> input = new HashMap<>();
        input.put("clientId", UUID.randomUUID().toString());
        input.put("itemId", item.get("id").asText()); input.put("type", type);
        input.put("quantity", quantity); input.put("reference", "DOC-001"); input.put("notes", "Test movement");
        if (type.equals("STOCK_COUNT")) input.put("expectedVersion", item.get("version").asLong());
        return input;
    }

    private String registerUser() {
        ResponseEntity<JsonNode> response = request(HttpMethod.POST, "/api/auth/register", null,
                Map.of("name", "Test User", "email", uniqueEmail(), "password", "CorrectPassword123!"));
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        return response.getBody().get("accessToken").asText();
    }

    private static String uniqueEmail() { return UUID.randomUUID() + "@example.com"; }

    private static Map<String, Object> item(String name, String sku, int quantity) {
        Map<String, Object> body = new HashMap<>();
        body.put("name", name); body.put("sku", sku); body.put("category", "Hardware");
        body.put("quantity", quantity); body.put("reorderLevel", 5);
        body.put("price", new BigDecimal("99.90")); body.put("notes", "Integration test item");
        return body;
    }

    private ResponseEntity<JsonNode> request(HttpMethod method, String endpoint, String token, Object body) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        if (token != null) headers.setBearerAuth(token);
        return http.exchange(endpoint, method, new HttpEntity<>(body, headers), JsonNode.class);
    }
}
