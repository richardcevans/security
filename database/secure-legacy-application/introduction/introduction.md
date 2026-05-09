# Securing a legacy application using Oracle Database Vault on Oracle Autonomous Database

## Introduction

<<<<<<< HEAD
In addition to its self-managing capabilities, Oracle Autonomous Database also integrates with Oracle Database Vault. Oracle Database Vault is a security-enhancement tool that provides an additional layer of security by restricting access to sensitive data and preventing unauthorized users from accessing or manipulating it. By combining the self-managing capabilities of Oracle Autonomous Database with the security features of Oracle Database Vault, organizations can benefit from both enhanced performance and improved security.

One of the key features of Oracle Autonomous Database is its ability to automatically tune itself for optimal performance. This is achieved through the use of machine learning algorithms that continually analyze database workloads and make adjustments to the database configuration in real-time. This allows Oracle Autonomous Database to deliver consistently high performance, even as workloads and data volumes change over time.

Overall, Oracle Autonomous Database and Oracle Database Vault are valuable tools for organizations looking to optimize their database performance and improve security. The combination of these two technologies allows organizations to take advantage of the self-managing capabilities of Oracle Autonomous Database, while also protecting sensitive data with the security features of Oracle Database Vault.
=======
Many enterprise applications still rely on legacy app servers and database architectures, making it difficult to enforce modern security controls. In this lab, you’ll migrate a legacy HR application running on GlassFish to **Oracle Autonomous Database (ADB)**—modernizing its data platform while preserving application functionality.

Participants will gain practical experience migrating a legacy application to a modern, cloud-native data platform, while implementing layered security controls that align with today’s robust security requiremens and governance standards. The lab emphasizes real-world techniques for monitoring data access, evaluating potential risks, and enforcing least-privilege policies in a controlled, non-disruptive way.

This lab is designed to showcase how Autonomous Database’s built-in security capabilities, including Database Vault realms and simulation mode, can help you strengthen data security, minimize privileged access risk, and modernize securely—without rewriting your application.
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd

![Lab Architecture](images/intro-architecture.png)

Estimated Time: 90 minutes

### Objectives

In this lab, you will complete the following tasks:

- Connect to the Glassfish legacy HR application
- Configure the Autonomous Database Instance
- Load and verify the data in the Glassfish application
- Enable Database Vault and verify the HR application
- Identify the connections to the EMPLOYEESEARCH_PROD schema
- Explore the Glassfish HR application functions with Database Vault enabled

### Prerequisites

<<<<<<< HEAD
This workshop assumes you have:
- An Oracle Cloud Infratructure tanancy account
- Familiarity with Database is desired
- Some understanding of cloud and database terms is helpful
- Familiarity with Oracle Cloud Infrastructure (OCI) is helpful
- Some basic understanding of data protection and security is a plus
- Some familiarity with Linux/Bash commands is helpful
=======
This is a 300-level lab:

- Recommended - Completion of the following workshops:
    - DB Security - Database Vault:  https://livelabs.oracle.com/pls/apex/f?p=133:180:124550529861240::::wid:682
    - Using Oracle Database Vault on Autonomous Database: https://livelabs.oracle.com/pls/apex/f?p=133:180:106941830077530::::wid:3071
- Access to an Oracle Cloud Infrastructure (OCI) tenancy and Cloud Shell
- Familiarity with basic RDBMS concepts is desired
- Basic understanding of cloud and database terms is helpful
- Familiarity with the basics Oracle Cloud Infrastructure (OCI)
- Basic navigation skills around Linux/Bash environments
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd

*Note: Throughout this workshop, if you ever find yourself struggling when it comes to finding your resources in Oracle Cloud, make sure both your compartment and region correspond to where you created the resource.*

## Want to learn more about Oracle Database Vault?
- [Oracle Database Vault Landing Page](https://www.oracle.com/security/database-security/database-vault/)
<<<<<<< HEAD
- [Introduction to Oracle Database Vault](https://docs.oracle.com/database/121/DVADM/dvintro.htm#DVADM001)
=======
- [Release 23 Oracle Database Vault Administrator's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/23/dvadm/release-changes.html)
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd
- [Additional Database Vault LiveLab](https://livelabs.oracle.com/pls/apex/r/dbpm/livelabs/view-workshop?wid=682&clear=RR,180&session=100352880546347)

## Acknowledgements

<<<<<<< HEAD
- **Author** - Ethan Shmargad, North America Specialists Hub
- **Creator** - Richard Evans, Senior Principle Product Manager
- **Last Updated By/Date** - Ethan Shmargad, September 2022
=======
- **Author** - Ethan Shmargad, Product Manager
- **Creator** - Richard Evans, Senior Principle Product Manager
- **Last Updated By/Date** - Ethan Shmargad, April 2025
>>>>>>> ecfd685b6409977b9a29d88ace059340a60acbbd
