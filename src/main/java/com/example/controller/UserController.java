package com.example.controller;

import com.example.model.User;
import com.example.service.UserService;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/users")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping("/{id}")
    public User getUser(@PathVariable Long id) {
        return userService.findById(id);
    }

    @GetMapping
    public Map<String, Object> getAllUsers(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(defaultValue = "createdAt,desc") String[] sort) {

        Sort.Direction direction = Sort.Direction.DESC;
        String sortField = "createdAt";

        if (sort.length > 0) {
            sortField = sort[0];
        }
        if (sort.length > 1) {
            direction = Sort.Direction.fromString(sort[1]);
        }

        Pageable pageable = PageRequest.of(page, size, Sort.by(direction, sortField));
        Page<User> userPage = userService.findAll(pageable);

        Map<String, Object> response = new HashMap<>();
        response.put("content", userPage.getContent());
        response.put("totalElements", userPage.getTotalElements());
        response.put("totalPages", userPage.getTotalPages());
        response.put("currentPage", userPage.getNumber());

        return response;
    }
}
