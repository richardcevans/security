package com.example.sampleapp.repository;

import com.example.sampleapp.model.Employee;
import org.springframework.stereotype.Repository;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

@Repository
public class EmployeeRepository {

    private static final String SELECT_ALL =
        "SELECT employee_id, first_name, last_name, job_code, department_id, ssn, phone_number, salary, user_name, manager_id FROM hr.employees ORDER BY employee_id";

    private static final String SELECT_BY_ID =
        "SELECT employee_id, first_name, last_name, job_code, department_id, ssn, phone_number, salary, user_name, manager_id FROM hr.employees WHERE employee_id = ?";

    public List<Employee> findAll(Connection conn) throws SQLException {
        List<Employee> employees = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(SELECT_ALL);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                employees.add(mapRow(rs));
            }
        }
        return employees;
    }

    public Employee findById(Connection conn, int id) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement(SELECT_BY_ID)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return mapRow(rs);
                }
            }
        }
        return null;
    }

    private Employee mapRow(ResultSet rs) throws SQLException {
        Employee e = new Employee();
        e.setEmployeeId(rs.getInt("employee_id"));
        e.setFirstName(rs.getString("first_name"));
        e.setLastName(rs.getString("last_name"));
        e.setJobCode(rs.getString("job_code"));
        e.setDepartmentId(rs.getObject("department_id") != null ? rs.getInt("department_id") : null);
        e.setSsn(rs.getString("ssn"));
        e.setPhoneNumber(rs.getString("phone_number"));
        e.setSalary(rs.getObject("salary") != null ? rs.getDouble("salary") : null);
        e.setUserName(rs.getString("user_name"));
        e.setManagerId(rs.getObject("manager_id") != null ? rs.getInt("manager_id") : null);
        return e;
    }
}
