package com.example.sampleapp;

import oracle.jdbc.pool.OracleDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

import jakarta.annotation.PostConstruct;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.security.cert.X509Certificate;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.Properties;

@Configuration
public class DataSourceConfig {

    @Value("${spring.datasource.url}")
    private String url;

    @PostConstruct
    public void init() {
        try {
            // Accept any certificate — equivalent to oracledb's ssl._create_unverified_context()
            SSLContext ctx = SSLContext.getInstance("TLS");
            ctx.init(null, new TrustManager[]{new X509TrustManager() {
                public void checkClientTrusted(X509Certificate[] c, String a) {}
                public void checkServerTrusted(X509Certificate[] c, String a) {}
                public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            }}, null);
            SSLContext.setDefault(ctx);
        } catch (Exception e) {
            throw new RuntimeException("Failed to configure SSL context", e);
        }
    }

    public Connection getConnection(String username, String password) throws SQLException {
        OracleDataSource ds = new OracleDataSource();
        ds.setURL(url);
        ds.setUser(username);
        ds.setPassword(password);
        Properties props = new Properties();
        props.setProperty("oracle.net.ssl_server_dn_match", "false");
        ds.setConnectionProperties(props);
        return ds.getConnection();
    }
}
