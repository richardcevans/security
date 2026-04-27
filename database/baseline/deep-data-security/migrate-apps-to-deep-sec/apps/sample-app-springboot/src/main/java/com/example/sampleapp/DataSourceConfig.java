package com.example.sampleapp;

import oracle.jdbc.pool.OracleDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

import jakarta.annotation.PostConstruct;
import java.security.Security;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.Properties;

@Configuration
public class DataSourceConfig {

    @Value("${spring.datasource.url}")
    private String url;

    @Value("${oracle.net.wallet_location}")
    private String walletLocation;

    @PostConstruct
    public void init() {
        Security.addProvider(new oracle.security.pki.OraclePKIProvider());
    }

    public Connection getConnection(String username, String password) throws SQLException {
        OracleDataSource ds = new OracleDataSource();
        ds.setURL(url);
        ds.setUser(username);
        ds.setPassword(password);

        Properties props = new Properties();
        props.setProperty("oracle.net.wallet_location", walletLocation);
        props.setProperty("oracle.net.ssl_server_dn_match", "false");
        ds.setConnectionProperties(props);

        return ds.getConnection();
    }
}
