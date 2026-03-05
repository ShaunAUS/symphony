package com.example.service;

import com.example.model.Dd;
import com.example.repository.DdRepository;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class DdService {

    private final DdRepository ddRepository;

    public DdService(DdRepository ddRepository) {
        this.ddRepository = ddRepository;
    }

    public Dd findById(Long id) {
        return ddRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Dd not found with id: " + id));
    }

    public List<Dd> findAll() {
        return ddRepository.findAll();
    }

    public Dd save(Dd dd) {
        return ddRepository.save(dd);
    }

    public void deleteById(Long id) {
        ddRepository.deleteById(id);
    }
}
