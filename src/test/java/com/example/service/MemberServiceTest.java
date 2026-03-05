package com.example.service;

import com.example.model.Member;
import com.example.repository.MemberRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Arrays;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class MemberServiceTest {

    @Mock
    private MemberRepository memberRepository;

    @InjectMocks
    private MemberService memberService;

    private Member member;

    @BeforeEach
    void setUp() {
        member = new Member();
        member.setId(1L);
        member.setEmail("test@example.com");
        member.setPassword("secret123");
    }

    @Test
    void findById_returnsMember() {
        when(memberRepository.findById(1L)).thenReturn(Optional.of(member));

        Member found = memberService.findById(1L);

        assertNotNull(found);
        assertEquals("test@example.com", found.getEmail());
    }

    @Test
    void findById_throwsWhenNotFound() {
        when(memberRepository.findById(99L)).thenReturn(Optional.empty());

        assertThrows(IllegalArgumentException.class, () -> memberService.findById(99L));
    }

    @Test
    void findAll_returnsAllMembers() {
        Member member2 = new Member();
        member2.setId(2L);
        member2.setEmail("other@example.com");
        member2.setPassword("pass456");

        when(memberRepository.findAll()).thenReturn(Arrays.asList(member, member2));

        List<Member> members = memberService.findAll();

        assertEquals(2, members.size());
    }

    @Test
    void save_persistsMember() {
        when(memberRepository.save(any(Member.class))).thenReturn(member);

        Member saved = memberService.save(member);

        assertNotNull(saved);
        assertEquals("test@example.com", saved.getEmail());
        verify(memberRepository).save(member);
    }
}
