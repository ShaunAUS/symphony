package com.example.service;

import com.example.model.Member;
import com.example.repository.MemberRepository;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.NoSuchElementException;

@Service
public class MemberService {

    private final MemberRepository memberRepository;

    public MemberService(MemberRepository memberRepository) {
        this.memberRepository = memberRepository;
    }

    public Member findById(Long id) {
        return memberRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Member not found with id: " + id));
    }

    public List<Member> findAll() {
        return memberRepository.findAll();
    }

    public Member save(Member member) {
        return memberRepository.save(member);
    }

    public Member update(Long id, Member memberDetails) {
        Member member = findById(id);
        member.setName(memberDetails.getName());
        member.setEmail(memberDetails.getEmail());
        return memberRepository.save(member);
    }

    public void delete(Long id) {
        Member member = findById(id);
        memberRepository.delete(member);
    }
}
