package com.example.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class MemberTest {

    @Test
    void createMember_withEmailAndPassword() {
        Member member = new Member();
        member.setEmail("test@example.com");
        member.setPassword("secret123");

        assertEquals("test@example.com", member.getEmail());
        assertEquals("secret123", member.getPassword());
    }

    @Test
    void newMember_hasNullId() {
        Member member = new Member();
        assertNull(member.getId());
    }

    @Test
    void setAndGetId() {
        Member member = new Member();
        member.setId(1L);
        assertEquals(1L, member.getId());
    }
}
