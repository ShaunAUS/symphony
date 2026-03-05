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
import java.util.NoSuchElementException;
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
        member.setName("John");
        member.setEmail("john@example.com");
    }

    @Test
    void findById_shouldReturnMember_whenMemberExists() {
        when(memberRepository.findById(1L)).thenReturn(Optional.of(member));

        Member found = memberService.findById(1L);

        assertEquals("John", found.getName());
        assertEquals("john@example.com", found.getEmail());
    }

    @Test
    void findById_shouldThrowException_whenMemberNotFound() {
        when(memberRepository.findById(1L)).thenReturn(Optional.empty());

        assertThrows(NoSuchElementException.class, () -> memberService.findById(1L));
    }

    @Test
    void findAll_shouldReturnAllMembers() {
        Member member2 = new Member();
        member2.setId(2L);
        member2.setName("Jane");
        member2.setEmail("jane@example.com");

        when(memberRepository.findAll()).thenReturn(Arrays.asList(member, member2));

        List<Member> members = memberService.findAll();

        assertEquals(2, members.size());
    }

    @Test
    void save_shouldReturnSavedMember() {
        when(memberRepository.save(any(Member.class))).thenReturn(member);

        Member saved = memberService.save(member);

        assertNotNull(saved);
        assertEquals("John", saved.getName());
    }

    @Test
    void update_shouldUpdateMemberFields() {
        Member updatedDetails = new Member();
        updatedDetails.setName("John Updated");
        updatedDetails.setEmail("john.updated@example.com");

        when(memberRepository.findById(1L)).thenReturn(Optional.of(member));
        when(memberRepository.save(any(Member.class))).thenReturn(member);

        Member updated = memberService.update(1L, updatedDetails);

        verify(memberRepository).save(any(Member.class));
        assertEquals("John Updated", member.getName());
        assertEquals("john.updated@example.com", member.getEmail());
    }

    @Test
    void delete_shouldDeleteMember_whenMemberExists() {
        when(memberRepository.findById(1L)).thenReturn(Optional.of(member));

        memberService.delete(1L);

        verify(memberRepository).delete(member);
    }

    @Test
    void delete_shouldThrowException_whenMemberNotFound() {
        when(memberRepository.findById(1L)).thenReturn(Optional.empty());

        assertThrows(NoSuchElementException.class, () -> memberService.delete(1L));
    }
}
