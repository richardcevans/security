package com.example.sampleapp.controller;

import com.example.sampleapp.DataSourceConfig;
import com.example.sampleapp.model.Employee;
import com.example.sampleapp.repository.EmployeeRepository;
import jakarta.servlet.http.HttpSession;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import java.sql.Connection;
import java.util.List;

@Controller
public class EmployeeController {

    private final EmployeeRepository employeeRepository;
    private final DataSourceConfig dataSourceConfig;

    public EmployeeController(EmployeeRepository employeeRepository, DataSourceConfig dataSourceConfig) {
        this.employeeRepository = employeeRepository;
        this.dataSourceConfig = dataSourceConfig;
    }

    @GetMapping("/")
    public String index(HttpSession session) {
        if (session.getAttribute("dbUser") == null) {
            return "redirect:/login";
        }
        return "redirect:/employees";
    }

    @GetMapping("/login")
    public String loginPage() {
        return "login";
    }

    @PostMapping("/login")
    public String login(@RequestParam String username, @RequestParam String password,
                        HttpSession session, Model model) {
        try (Connection conn = dataSourceConfig.getConnection(username, password)) {
            session.setAttribute("dbUser", username);
            session.setAttribute("dbPass", password);
            return "redirect:/employees";
        } catch (Exception e) {
            model.addAttribute("error", "Login failed: " + e.getMessage());
            return "login";
        }
    }

    @GetMapping("/logout")
    public String logout(HttpSession session) {
        session.invalidate();
        return "redirect:/login";
    }

    @GetMapping("/employees")
    public String listEmployees(HttpSession session, Model model) {
        String user = (String) session.getAttribute("dbUser");
        String pass = (String) session.getAttribute("dbPass");
        if (user == null) return "redirect:/login";

        try (Connection conn = dataSourceConfig.getConnection(user, pass)) {
            List<Employee> employees = employeeRepository.findAll(conn);
            model.addAttribute("employees", employees);
            model.addAttribute("currentUser", user);
            return "employees";
        } catch (Exception e) {
            model.addAttribute("error", "Database error: " + e.getMessage());
            return "employees";
        }
    }

    @GetMapping("/api/employees")
    @ResponseBody
    public List<Employee> apiListEmployees(HttpSession session) throws Exception {
        String user = (String) session.getAttribute("dbUser");
        String pass = (String) session.getAttribute("dbPass");
        if (user == null) throw new RuntimeException("Not authenticated");

        try (Connection conn = dataSourceConfig.getConnection(user, pass)) {
            return employeeRepository.findAll(conn);
        }
    }

    @GetMapping("/api/employees/{id}")
    @ResponseBody
    public Employee apiGetEmployee(@PathVariable int id, HttpSession session) throws Exception {
        String user = (String) session.getAttribute("dbUser");
        String pass = (String) session.getAttribute("dbPass");
        if (user == null) throw new RuntimeException("Not authenticated");

        try (Connection conn = dataSourceConfig.getConnection(user, pass)) {
            return employeeRepository.findById(conn, id);
        }
    }
}
