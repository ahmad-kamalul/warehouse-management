package com.ahmad.warehousemanagement;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/operations")
class OperationsController {
    private final OperationsService service;
    OperationsController(OperationsService service) { this.service = service; }
    @GetMapping("/master")
    OperationsService.Master master(@AuthenticationPrincipal Jwt jwt) {
        return service.master(UUID.fromString(jwt.getSubject()));
    }
    @PostMapping("/transactions")
    OperationsService.Receipt upload(@AuthenticationPrincipal Jwt jwt,
            @Valid @RequestBody OperationsService.Input input) {
        return service.upload(UUID.fromString(jwt.getSubject()), input);
    }
    @GetMapping("/transactions")
    List<OperationsService.Receipt> history(@AuthenticationPrincipal Jwt jwt) {
        return service.history(UUID.fromString(jwt.getSubject()));
    }
}
