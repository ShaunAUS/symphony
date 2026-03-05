package com.example.controller;

import com.example.model.Member;
import com.example.service.MemberService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class MemberControllerTest {

    @Mock
    private MemberService memberService;

    @InjectMocks
    private MemberController memberController;

    private Member member;

    @BeforeEach
    void setUp() {
        member = new Member();
        member.setId(1L);
        member.setName("John");
        member.setEmail("john@example.com");
    }

    @Test
    void getMember_shouldReturnMember() {
        when(memberService.findById(1L)).thenReturn(member);

        Member result = memberController.getMember(1L);

        assertEquals("John", result.getName());
    }

    @Test
    void getAllMembers_shouldReturnList() {
        when(memberService.findAll()).thenReturn(Arrays.asList(member));

        List<Member> result = memberController.getAllMembers();

        assertEquals(1, result.size());
    }

    @Test
    void createMember_shouldReturnCreatedMember() {
        when(memberService.save(any(Member.class))).thenReturn(member);

        Member result = memberController.createMember(member);

        assertNotNull(result);
        assertEquals("John", result.getName());
    }

    @Test
    void updateMember_shouldReturnUpdatedMember() {
        when(memberService.update(eq(1L), any(Member.class))).thenReturn(member);

        Member result = memberController.updateMember(1L, member);

        assertNotNull(result);
    }

    @Test
    void deleteMember_shouldCallService() {
        memberController.deleteMember(1L);

        verify(memberService).delete(1L);
    }
}
