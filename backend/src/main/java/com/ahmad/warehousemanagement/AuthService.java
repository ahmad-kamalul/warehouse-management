package com.ahmad.warehousemanagement;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Locale;
import java.util.UUID;
import static com.ahmad.warehousemanagement.ApiModels.*;

@Service
class AuthService {
    private static final Logger log = LoggerFactory.getLogger(AuthService.class);
    private final UserRepository users;
    private final PasswordEncoder passwords;
    private final JwtEncoder tokens;
    private final String issuer;
    private final long ttlSeconds;

    AuthService(UserRepository users, PasswordEncoder passwords, JwtEncoder tokens,
                @Value("${app.jwt.issuer}") String issuer,
                @Value("${app.jwt.ttl-seconds}") long ttlSeconds) {
        this.users = users;
        this.passwords = passwords;
        this.tokens = tokens;
        this.issuer = issuer;
        this.ttlSeconds = ttlSeconds;
    }

    @Transactional
    public AuthResponse register(RegisterRequest request) {
        validatePasswordBytes(request.password());
        String email = normalizeEmail(request.email());
        if (users.existsByEmail(email)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "An account with this email already exists");
        }
        AppUser user = new AppUser(request.name().trim(), email, passwords.encode(request.password()));
        // Unique database constraint also protects concurrent registrations.
        users.saveAndFlush(user);
        log.info("Registered user {}", user.id);
        return issueToken(user);
    }

    @Transactional(readOnly = true)
    public AuthResponse login(LoginRequest request) {
        validatePasswordBytes(request.password());
        AppUser user = users.findByEmail(normalizeEmail(request.email()))
                .filter(found -> passwords.matches(request.password(), found.passwordHash))
                .orElseThrow(() -> new BadCredentialsException("Invalid email or password"));
        return issueToken(user);
    }

    @Transactional(readOnly = true)
    public UserView me(UUID userId) {
        return view(users.findById(userId).orElseThrow(() ->
                new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Account unavailable")));
    }

    private AuthResponse issueToken(AppUser user) {
        Instant now = Instant.now();
        JwtClaimsSet claims = JwtClaimsSet.builder().issuer(issuer)
                // User ID remains stable if email/name changes later.
                .subject(user.id.toString()).issuedAt(now)
                .expiresAt(now.plusSeconds(ttlSeconds)).build();
        JwsHeader header = JwsHeader.with(MacAlgorithm.HS256).build();
        String token = tokens.encode(JwtEncoderParameters.from(header, claims)).getTokenValue();
        return new AuthResponse(token, "Bearer", ttlSeconds, view(user));
    }

    private static String normalizeEmail(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }

    private static UserView view(AppUser user) {
        return new UserView(user.id, user.name, user.email);
    }

    private static void validatePasswordBytes(String password) {
        // BCrypt's limit is bytes, not Java character count.
        if (password.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Password must not exceed 72 UTF-8 bytes");
        }
    }
}
