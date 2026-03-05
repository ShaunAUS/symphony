package com.example.service;

import com.example.model.User;
import com.example.repository.UserRepository;
import org.springframework.stereotype.Service;

@Service
public class UserService {

    private final UserRepository userRepository;

    public UserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    // BUG: This throws NullPointerException when user is not found
    public User findById(Long id) {
        return userRepository.findById(id).get();
    }

    public java.util.List<User> findAll() {
        return userRepository.findAll();
    }
}
