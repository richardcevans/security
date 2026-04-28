package com.example.sampleapp;

import oracle.jdbc.pool.OracleDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

import java.sql.Connection;
import java.sql.SQLException;

@Configuration
public class DataSourceConfig {

    @Value("${spring.datasource.url}")
    private String url;

    public Connection getConnection(String username, String password) throws SQLException {
        OracleDataSource ds = new OracleDataSource();
        ds.setURL(url);
        return ds.getConnection(username, password);
    }
}
