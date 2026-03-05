package com.example.controller;

import com.example.model.Dd;
import com.example.service.DdService;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/dd")
public class DdController {

    private final DdService ddService;

    public DdController(DdService ddService) {
        this.ddService = ddService;
    }

    @GetMapping("/{id}")
    public Dd getById(@PathVariable Long id) {
        return ddService.findById(id);
    }

    @GetMapping
    public List<Dd> getAll() {
        return ddService.findAll();
    }

    @PostMapping
    public Dd create(@RequestBody Dd dd) {
        return ddService.save(dd);
    }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable Long id) {
        ddService.deleteById(id);
    }
}
