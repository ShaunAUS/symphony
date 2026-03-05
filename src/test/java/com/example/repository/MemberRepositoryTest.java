package com.example.repository;

import com.example.model.Member;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

@DataJpaTest
class MemberRepositoryTest {

    @Autowired
    private TestEntityManager entityManager;

    @Autowired
    private MemberRepository memberRepository;

    @Test
    void saveMember_andFindById() {
        Member member = new Member();
        member.setEmail("test@example.com");
        member.setPassword("secret123");

        Member saved = entityManager.persistAndFlush(member);

        Optional<Member> found = memberRepository.findById(saved.getId());
        assertTrue(found.isPresent());
        assertEquals("test@example.com", found.get().getEmail());
        assertEquals("secret123", found.get().getPassword());
    }

    @Test
    void findByEmail_returnsMember() {
        Member member = new Member();
        member.setEmail("find@example.com");
        member.setPassword("pass123");

        entityManager.persistAndFlush(member);

        Optional<Member> found = memberRepository.findByEmail("find@example.com");
        assertTrue(found.isPresent());
        assertEquals("find@example.com", found.get().getEmail());
    }

    @Test
    void findByEmail_returnsEmptyForNonExistent() {
        Optional<Member> found = memberRepository.findByEmail("nonexistent@example.com");
        assertFalse(found.isPresent());
    }
}
