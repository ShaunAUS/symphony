package com.example.repository;

import com.example.model.Dd;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface DdRepository extends JpaRepository<Dd, Long> {
}
