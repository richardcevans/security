package com.example.sampleapp.model;

public class Employee {
    private int employeeId;
    private String firstName;
    private String lastName;
    private String jobCode;
    private Integer departmentId;
    private String ssn;
    private String phoneNumber;
    private Double salary;
    private String userName;
    private Integer managerId;

    public int getEmployeeId() { return employeeId; }
    public void setEmployeeId(int employeeId) { this.employeeId = employeeId; }
    public String getFirstName() { return firstName; }
    public void setFirstName(String firstName) { this.firstName = firstName; }
    public String getLastName() { return lastName; }
    public void setLastName(String lastName) { this.lastName = lastName; }
    public String getJobCode() { return jobCode; }
    public void setJobCode(String jobCode) { this.jobCode = jobCode; }
    public Integer getDepartmentId() { return departmentId; }
    public void setDepartmentId(Integer departmentId) { this.departmentId = departmentId; }
    public String getSsn() { return ssn; }
    public void setSsn(String ssn) { this.ssn = ssn; }
    public String getPhoneNumber() { return phoneNumber; }
    public void setPhoneNumber(String phoneNumber) { this.phoneNumber = phoneNumber; }
    public Double getSalary() { return salary; }
    public void setSalary(Double salary) { this.salary = salary; }
    public String getUserName() { return userName; }
    public void setUserName(String userName) { this.userName = userName; }
    public Integer getManagerId() { return managerId; }
    public void setManagerId(Integer managerId) { this.managerId = managerId; }
}
