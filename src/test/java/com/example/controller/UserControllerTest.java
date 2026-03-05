package com.example.controller;

import com.example.dto.PagedResponse;
import com.example.model.User;
import com.example.service.UserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

import java.time.LocalDateTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class UserControllerTest {

    @Mock
    private UserService userService;

    @InjectMocks
    private UserController userController;

    private User testUser;

    @BeforeEach
    void setUp() {
        testUser = new User();
        testUser.setId(1L);
        testUser.setName("Test User");
        testUser.setEmail("test@example.com");
        testUser.setCreatedAt(LocalDateTime.now());
    }

    @Test
    void getAllUsers_withDefaultParameters_returnsPagedResponse() {
        Page<User> page = new PageImpl<>(List.of(testUser));
        when(userService.findAll(any(Pageable.class))).thenReturn(page);

        PagedResponse<User> response = userController.getAllUsers(0, 20, new String[]{"createdAt", "desc"});

        assertEquals(1, response.getTotalElements());
        assertEquals(1, response.getTotalPages());
        assertEquals(0, response.getCurrentPage());
        assertEquals(1, response.getContent().size());
        assertEquals("Test User", response.getContent().get(0).getName());
    }

    @Test
    void getAllUsers_withCustomPageAndSize_passesCorrectPageable() {
        Page<User> page = new PageImpl<>(List.of(testUser));
        when(userService.findAll(any(Pageable.class))).thenReturn(page);

        userController.getAllUsers(2, 10, new String[]{"createdAt", "desc"});

        ArgumentCaptor<Pageable> captor = ArgumentCaptor.forClass(Pageable.class);
        verify(userService).findAll(captor.capture());
        Pageable pageable = captor.getValue();
        assertEquals(2, pageable.getPageNumber());
        assertEquals(10, pageable.getPageSize());
    }

    @Test
    void getAllUsers_withSortParameter_appliesSort() {
        Page<User> page = new PageImpl<>(List.of(testUser));
        when(userService.findAll(any(Pageable.class))).thenReturn(page);

        userController.getAllUsers(0, 20, new String[]{"createdAt", "asc"});

        ArgumentCaptor<Pageable> captor = ArgumentCaptor.forClass(Pageable.class);
        verify(userService).findAll(captor.capture());
        Sort sort = captor.getValue().getSort();
        Sort.Order order = sort.getOrderFor("createdAt");
        assertNotNull(order);
        assertEquals(Sort.Direction.ASC, order.getDirection());
    }

    @Test
    void getAllUsers_withEmptyPage_returnsEmptyContent() {
        Page<User> emptyPage = new PageImpl<>(List.of());
        when(userService.findAll(any(Pageable.class))).thenReturn(emptyPage);

        PagedResponse<User> response = userController.getAllUsers(0, 20, new String[]{"createdAt", "desc"});

        assertEquals(0, response.getTotalElements());
        assertEquals(1, response.getTotalPages());
        assertEquals(0, response.getCurrentPage());
        assertTrue(response.getContent().isEmpty());
    }
}
