package com.example.sampleapp;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;

@SpringBootApplication(exclude = {DataSourceAutoConfiguration.class})
public class SampleAppApplication {
    public static void main(String[] args) {
        SpringApplication.run(SampleAppApplication.class, args);
    }
}
