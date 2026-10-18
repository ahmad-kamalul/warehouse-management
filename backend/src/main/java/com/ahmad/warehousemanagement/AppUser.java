package com.ahmad.warehousemanagement;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "app_users")
class AppUser {
    @Id @GeneratedValue(strategy = GenerationType.UUID)
    UUID id;
    @Column(nullable = false, length = 100)
    String name;
    @Column(nullable = false, unique = true, length = 254)
    String email;
    @Column(name = "password_hash", nullable = false, length = 100)
    String passwordHash;
    @Column(name = "created_at", nullable = false, updatable = false)
    Instant createdAt;

    protected AppUser() {}

    AppUser(String name, String email, String passwordHash) {
        this.name = name;
        this.email = email;
        this.passwordHash = passwordHash;
        this.createdAt = Instant.now();
    }
}
