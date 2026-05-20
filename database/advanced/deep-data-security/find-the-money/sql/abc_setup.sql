-- =============================================================================
-- ABC_SETUP.SQL
-- Acme Banking Company (ABC) -- Deep Data Security Lab
-- Oracle AI Database 26ai / ADB-S Always Free
--
-- Run as ADMIN via Database Actions SQL Worksheet
-- Estimated runtime: 2-3 minutes
--
-- Creates:
--   Schema user:   ABC
--   Service acct:  ABC_AGENT_SVC  (PAF SQL Query Node)
--   Personas:      8 database users for SQLcl policy testing
--   Tables:        BRANCHES, STAFF, CUSTOMERS, ACCOUNTS,
--                  TRANSACTIONS, CREDIT_CARDS, ABC_REP_ASSIGNMENTS
--   View:          V_CUSTOMER_PORTAL
-- =============================================================================

-- -----------------------------------------------------------------------------
-- SECTION 1: CLEANUP (safe to re-run)
-- -----------------------------------------------------------------------------
BEGIN
  FOR u IN (
    SELECT username FROM dba_users
    WHERE username IN (
      'ABC','ABC_AGENT_SVC',
      'ALICE_CHEN','BOB_MARTINEZ','DIANA_OKAFOR','FRANK_RUSSO',
      'REP_SARAH_TORRES','REP_JAMES_WHITFIELD',
      'MGR_LINDA_CHEN','AUDIT_USER_ABC'
    )
  ) LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- SECTION 2: SCHEMA AND SERVICE ACCOUNT
-- -----------------------------------------------------------------------------

-- Main schema
CREATE USER abc IDENTIFIED BY "WelcomeABC#2026"
  DEFAULT TABLESPACE DATA
  QUOTA UNLIMITED ON DATA;

GRANT CONNECT, RESOURCE TO abc;
GRANT CREATE VIEW TO abc;
GRANT CREATE PROCEDURE TO abc;
GRANT CREATE SEQUENCE TO abc;

-- PAF SQL Query Node service account
-- This account connects to ADB-S; Deep Data Security enforces
-- end-user identity from the JWT regardless of this service account
CREATE USER abc_agent_svc IDENTIFIED BY "AgentSvc#2026"
  DEFAULT TABLESPACE DATA
  QUOTA 0 ON DATA;

GRANT CONNECT TO abc_agent_svc;

-- -----------------------------------------------------------------------------
-- SECTION 3: PERSONA DATABASE USERS
-- Used for direct SQLcl testing of DDS policies in Phase 3
-- These map to Entra ID users by convention; EMAIL column is the
-- authoritative identity binding for DDS policy evaluation
-- -----------------------------------------------------------------------------

CREATE USER alice_chen          IDENTIFIED BY "LabUser#2026" QUOTA 0 ON DATA;
CREATE USER bob_martinez        IDENTIFIED BY "LabUser#2026" QUOTA 0 ON DATA;
CREATE USER diana_okafor        IDENTIFIED BY "LabUser#2026" QUOTA 0 ON DATA;
CREATE USER frank_russo         IDENTIFIED BY "LabUser#2026" QUOTA 0 ON DATA;
CREATE USER rep_sarah_torres    IDENTIFIED BY "LabUser#2026" QUOTA 0 ON DATA;
CREATE USER rep_james_whitfield IDENTIFIED BY "LabUser#2026" QUOTA 0 ON DATA;
CREATE USER mgr_linda_chen      IDENTIFIED BY "LabUser#2026" QUOTA 0 ON DATA;
CREATE USER audit_user_abc      IDENTIFIED BY "LabUser#2026" QUOTA 0 ON DATA;

GRANT CONNECT TO alice_chen, bob_martinez, diana_okafor, frank_russo,
                 rep_sarah_torres, rep_james_whitfield,
                 mgr_linda_chen, audit_user_abc;

-- -----------------------------------------------------------------------------
-- SECTION 4: TABLES
-- -----------------------------------------------------------------------------

-- BRANCHES
CREATE TABLE abc.branches (
  branch_id       NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  branch_name     VARCHAR2(100)  NOT NULL,
  address         VARCHAR2(200),
  city            VARCHAR2(100),
  state           CHAR(2),
  zip             VARCHAR2(10),
  phone           VARCHAR2(20),
  manager_email   VARCHAR2(100)
);

-- STAFF (customer service reps and managers)
CREATE TABLE abc.staff (
  staff_id        NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  first_name      VARCHAR2(50)   NOT NULL,
  last_name       VARCHAR2(50)   NOT NULL,
  email           VARCHAR2(100)  NOT NULL UNIQUE,
  role            VARCHAR2(30)   NOT NULL,  -- SERVICE_REP, BRANCH_MANAGER, AUDITOR
  branch_id       NUMBER         REFERENCES abc.branches(branch_id),
  hire_date       DATE           DEFAULT SYSDATE,
  active_flag     CHAR(1)        DEFAULT 'Y'
);

-- CUSTOMERS
CREATE TABLE abc.customers (
  customer_id     NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  first_name      VARCHAR2(50)   NOT NULL,
  last_name       VARCHAR2(50)   NOT NULL,
  ssn             VARCHAR2(11)   NOT NULL,   -- format: XXX-XX-XXXX
  email           VARCHAR2(100)  NOT NULL UNIQUE,  -- matches Entra ID UPN
  phone           VARCHAR2(20),
  address         VARCHAR2(200),
  city            VARCHAR2(100),
  state           CHAR(2),
  zip             VARCHAR2(10),
  customer_tier   VARCHAR2(20)   DEFAULT 'STANDARD',  -- STANDARD, PREMIUM
  branch_id       NUMBER         REFERENCES abc.branches(branch_id),
  assigned_rep_id NUMBER         REFERENCES abc.staff(staff_id),
  account_status  VARCHAR2(20)   DEFAULT 'ACTIVE',  -- ACTIVE, DELINQUENT, COLLECTIONS
  collections_flag CHAR(1)       DEFAULT 'N',
  created_date    DATE           DEFAULT SYSDATE
);

-- ACCOUNTS
CREATE TABLE abc.accounts (
  account_id      NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id     NUMBER         NOT NULL REFERENCES abc.customers(customer_id),
  account_number  VARCHAR2(20)   NOT NULL UNIQUE,
  account_type    VARCHAR2(20)   NOT NULL,  -- CHECKING, SAVINGS, LOAN, CREDIT
  balance         NUMBER(15,2)   DEFAULT 0,
  credit_limit    NUMBER(15,2),             -- credit/loan accounts only
  status          VARCHAR2(20)   DEFAULT 'ACTIVE',
                                            -- ACTIVE, OVERDRAWN, OVERLIMIT, DELINQUENT
  overdraft_count NUMBER         DEFAULT 0,
  opened_date     DATE           DEFAULT SYSDATE,
  last_updated    TIMESTAMP      DEFAULT SYSTIMESTAMP
);

-- TRANSACTIONS
CREATE TABLE abc.transactions (
  transaction_id    NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id        NUMBER        NOT NULL REFERENCES abc.accounts(account_id),
  transaction_date  TIMESTAMP     NOT NULL,
  amount            NUMBER(15,2)  NOT NULL,  -- negative=debit, positive=credit
  merchant_name     VARCHAR2(200),
  transaction_type  VARCHAR2(30)  NOT NULL,
                    -- PURCHASE, ATM_WITHDRAWAL, TRANSFER, PAYMENT, WIRE, DEPOSIT
  fraud_flag        CHAR(1)       DEFAULT 'N',
  fraud_reason      VARCHAR2(500),           -- masked from customer-facing roles
  bsa_suspicious    CHAR(1)       DEFAULT 'N',
  bsa_reason        VARCHAR2(500),           -- masked from customer-facing roles
  channel           VARCHAR2(30)  DEFAULT 'ONLINE',
                    -- BRANCH, ATM, ONLINE, MOBILE, WIRE
  reference_number  VARCHAR2(50)
);

-- CREDIT_CARDS
CREATE TABLE abc.credit_cards (
  card_id           NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id       NUMBER        NOT NULL REFERENCES abc.customers(customer_id),
  card_number       VARCHAR2(19)  NOT NULL UNIQUE,  -- format: XXXX-XXXX-XXXX-XXXX
  card_type         VARCHAR2(20)  NOT NULL,          -- VISA, MASTERCARD, AMEX
  credit_limit      NUMBER(15,2)  NOT NULL,
  current_balance   NUMBER(15,2)  DEFAULT 0,
  available_credit  NUMBER(15,2)  GENERATED ALWAYS AS (credit_limit - current_balance) VIRTUAL,
  overlimit_flag    CHAR(1)       DEFAULT 'N',
  overlimit_amount  NUMBER(15,2)  DEFAULT 0,
  apr               NUMBER(5,2),
  statement_date    DATE,
  payment_due_date  DATE,
  minimum_payment   NUMBER(15,2),
  status            VARCHAR2(20)  DEFAULT 'ACTIVE'  -- ACTIVE, FROZEN, CANCELLED
);

-- REP ASSIGNMENT TABLE
-- Drives service rep row-level policy
CREATE TABLE abc.abc_rep_assignments (
  assignment_id   NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  staff_id        NUMBER         NOT NULL REFERENCES abc.staff(staff_id),
  customer_id     NUMBER         NOT NULL REFERENCES abc.customers(customer_id),
  rep_email       VARCHAR2(100)  NOT NULL,  -- denormalized for DDS policy join
  assigned_date   DATE           DEFAULT SYSDATE,
  CONSTRAINT uq_rep_customer UNIQUE (staff_id, customer_id)
);

-- Indexes
CREATE INDEX abc.idx_accounts_customer    ON abc.accounts(customer_id);
CREATE INDEX abc.idx_transactions_account ON abc.transactions(account_id);
CREATE INDEX abc.idx_transactions_date    ON abc.transactions(transaction_date);
CREATE INDEX abc.idx_creditcards_customer ON abc.credit_cards(customer_id);
CREATE INDEX abc.idx_customers_email      ON abc.customers(email);
CREATE INDEX abc.idx_repassign_email      ON abc.abc_rep_assignments(rep_email);
CREATE INDEX abc.idx_repassign_customer   ON abc.abc_rep_assignments(customer_id);

-- -----------------------------------------------------------------------------
-- SECTION 5: REFERENCE DATA
-- -----------------------------------------------------------------------------

INSERT INTO abc.branches (branch_name, address, city, state, zip, phone, manager_email)
VALUES ('Branch 001 - Downtown', '100 Main Street', 'San Antonio', 'TX', '78205',
        '210-555-0100', 'linda.chen@abcbank.lab');

INSERT INTO abc.branches (branch_name, address, city, state, zip, phone, manager_email)
VALUES ('Branch 002 - Northside', '4500 Loop 1604 N', 'San Antonio', 'TX', '78249',
        '210-555-0200', 'mgr.north@abcbank.lab');

COMMIT;

-- STAFF
INSERT INTO abc.staff (first_name, last_name, email, role, branch_id, hire_date)
VALUES ('Sarah', 'Torres', 'sarah.torres@abcbank.lab', 'SERVICE_REP', 1, DATE '2021-03-15');

INSERT INTO abc.staff (first_name, last_name, email, role, branch_id, hire_date)
VALUES ('James', 'Whitfield', 'james.whitfield@abcbank.lab', 'SERVICE_REP', 1, DATE '2022-07-01');

INSERT INTO abc.staff (first_name, last_name, email, role, branch_id, hire_date)
VALUES ('Linda', 'Chen', 'linda.chen@abcbank.lab', 'BRANCH_MANAGER', 1, DATE '2018-01-10');

INSERT INTO abc.staff (first_name, last_name, email, role, branch_id, hire_date)
VALUES ('Audit', 'User', 'audit.user@abcbank.lab', 'AUDITOR', NULL, DATE '2020-06-01');

COMMIT;

-- -----------------------------------------------------------------------------
-- SECTION 6: CUSTOMERS
-- -----------------------------------------------------------------------------

-- Alice Chen: baseline standard customer, good standing
INSERT INTO abc.customers (
  first_name, last_name, ssn, email, phone,
  address, city, state, zip,
  customer_tier, branch_id, assigned_rep_id, account_status, collections_flag
) VALUES (
  'Alice', 'Chen', '541-77-3821', 'alice.chen@abcbank.lab', '210-555-1001',
  '214 Oak Hollow Dr', 'San Antonio', 'TX', '78230',
  'STANDARD', 1,
  (SELECT staff_id FROM abc.staff WHERE email = 'sarah.torres@abcbank.lab'),
  'ACTIVE', 'N'
);

-- Bob Martinez: financially stressed, overdrafts, BSA-flagged transactions
INSERT INTO abc.customers (
  first_name, last_name, ssn, email, phone,
  address, city, state, zip,
  customer_tier, branch_id, assigned_rep_id, account_status, collections_flag
) VALUES (
  'Bob', 'Martinez', '382-55-9147', 'bob.martinez@abcbank.lab', '210-555-1002',
  '7823 Blanco Rd Apt 4B', 'San Antonio', 'TX', '78216',
  'STANDARD', 1,
  (SELECT staff_id FROM abc.staff WHERE email = 'sarah.torres@abcbank.lab'),
  'ACTIVE', 'N'
);

-- Diana Okafor: premium customer, high balance, over-limit credit card
INSERT INTO abc.customers (
  first_name, last_name, ssn, email, phone,
  address, city, state, zip,
  customer_tier, branch_id, assigned_rep_id, account_status, collections_flag
) VALUES (
  'Diana', 'Okafor', '719-34-6205', 'diana.okafor@abcbank.lab', '210-555-1003',
  '1 Dominion Ridge', 'San Antonio', 'TX', '78257',
  'PREMIUM', 1,
  (SELECT staff_id FROM abc.staff WHERE email = 'james.whitfield@abcbank.lab'),
  'ACTIVE', 'N'
);

-- Frank Russo: delinquent loan, in collections
INSERT INTO abc.customers (
  first_name, last_name, ssn, email, phone,
  address, city, state, zip,
  customer_tier, branch_id, assigned_rep_id, account_status, collections_flag
) VALUES (
  'Frank', 'Russo', '203-68-4471', 'frank.russo@abcbank.lab', '210-555-1004',
  '9902 Culebra Rd', 'San Antonio', 'TX', '78251',
  'STANDARD', 1,
  (SELECT staff_id FROM abc.staff WHERE email = 'james.whitfield@abcbank.lab'),
  'COLLECTIONS', 'Y'
);

COMMIT;

-- -----------------------------------------------------------------------------
-- SECTION 7: ACCOUNTS
-- -----------------------------------------------------------------------------

-- Alice: checking + savings
INSERT INTO abc.accounts (customer_id, account_number, account_type, balance, status, opened_date)
VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'alice.chen@abcbank.lab'),
  'CHK-0010-4821', 'CHECKING', 3847.52, 'ACTIVE', DATE '2019-04-12'
);

INSERT INTO abc.accounts (customer_id, account_number, account_type, balance, status, opened_date)
VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'alice.chen@abcbank.lab'),
  'SAV-0010-4822', 'SAVINGS', 12450.00, 'ACTIVE', DATE '2019-04-12'
);

-- Bob: checking (overdrawn twice this month), savings (low)
INSERT INTO abc.accounts (customer_id, account_number, account_type, balance, status, overdraft_count, opened_date)
VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'bob.martinez@abcbank.lab'),
  'CHK-0020-7731', 'CHECKING', -142.37, 'OVERDRAWN', 2, DATE '2020-11-03'
);

INSERT INTO abc.accounts (customer_id, account_number, account_type, balance, status, opened_date)
VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'bob.martinez@abcbank.lab'),
  'SAV-0020-7732', 'SAVINGS', 88.14, 'ACTIVE', DATE '2020-11-03'
);

-- Diana: premium checking (high balance), savings
INSERT INTO abc.accounts (customer_id, account_number, account_type, balance, status, opened_date)
VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'diana.okafor@abcbank.lab'),
  'CHK-0030-2291', 'CHECKING', 87432.19, 'ACTIVE', DATE '2017-08-22'
);

INSERT INTO abc.accounts (customer_id, account_number, account_type, balance, status, opened_date)
VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'diana.okafor@abcbank.lab'),
  'SAV-0030-2292', 'SAVINGS', 143800.00, 'ACTIVE', DATE '2017-08-22'
);

-- Frank: checking (low), auto loan (delinquent)
INSERT INTO abc.accounts (customer_id, account_number, account_type, balance, status, opened_date)
VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'frank.russo@abcbank.lab'),
  'CHK-0040-9901', 'CHECKING', 214.88, 'ACTIVE', DATE '2018-02-14'
);

INSERT INTO abc.accounts (
  customer_id, account_number, account_type, balance, credit_limit, status, opened_date
) VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'frank.russo@abcbank.lab'),
  'LOAN-0040-9902', 'LOAN', 18450.00, 24000.00, 'DELINQUENT', DATE '2022-01-15'
);

COMMIT;

-- -----------------------------------------------------------------------------
-- SECTION 8: CREDIT CARDS
-- -----------------------------------------------------------------------------

-- Alice: Visa, good standing
INSERT INTO abc.credit_cards (
  customer_id, card_number, card_type, credit_limit, current_balance,
  overlimit_flag, overlimit_amount, apr,
  statement_date, payment_due_date, minimum_payment, status
) VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'alice.chen@abcbank.lab'),
  '4532-1187-3421-8821', 'VISA', 8000.00, 1243.67,
  'N', 0, 19.99,
  LAST_DAY(SYSDATE - 30), LAST_DAY(SYSDATE - 30) + 25, 35.00, 'ACTIVE'
);

-- Bob: Mastercard, near limit
INSERT INTO abc.credit_cards (
  customer_id, card_number, card_type, credit_limit, current_balance,
  overlimit_flag, overlimit_amount, apr,
  statement_date, payment_due_date, minimum_payment, status
) VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'bob.martinez@abcbank.lab'),
  '5412-7533-9841-2207', 'MASTERCARD', 3000.00, 2887.43,
  'N', 0, 24.99,
  LAST_DAY(SYSDATE - 30), LAST_DAY(SYSDATE - 30) + 25, 75.00, 'ACTIVE'
);

-- Diana: Amex Platinum, OVER LIMIT
INSERT INTO abc.credit_cards (
  customer_id, card_number, card_type, credit_limit, current_balance,
  overlimit_flag, overlimit_amount, apr,
  statement_date, payment_due_date, minimum_payment, status
) VALUES (
  (SELECT customer_id FROM abc.customers WHERE email = 'diana.okafor@abcbank.lab'),
  '3782-822463-10005', 'AMEX', 50000.00, 51847.32,
  'Y', 1847.32, 17.99,
  LAST_DAY(SYSDATE - 30), LAST_DAY(SYSDATE - 30) + 25, 1500.00, 'ACTIVE'
);

COMMIT;

-- -----------------------------------------------------------------------------
-- SECTION 9: TRANSACTIONS
-- -----------------------------------------------------------------------------

-- Alice: normal transaction history
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0010-4821'),
  SYSTIMESTAMP - INTERVAL '3' DAY, -87.43, 'HEB Grocery', 'PURCHASE', 'MOBILE'
);
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0010-4821'),
  SYSTIMESTAMP - INTERVAL '7' DAY, -124.00, 'CPS Energy', 'PURCHASE', 'ONLINE'
);
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0010-4821'),
  SYSTIMESTAMP - INTERVAL '10' DAY, 3200.00, 'Direct Deposit - Employer', 'DEPOSIT', 'ONLINE'
);
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0010-4821'),
  SYSTIMESTAMP - INTERVAL '14' DAY, -54.12, 'Valero Gas Station', 'PURCHASE', 'MOBILE'
);

-- Bob: overdrafts + BSA structuring pattern
-- The structuring sequence: large ATM withdrawal, three international wires,
-- second large ATM withdrawal from different branch.
-- BSA_SUSPICIOUS = Y on all three. FRAUD_REASON masked from customer role.

INSERT INTO abc.transactions (
  account_id, transaction_date, amount, merchant_name,
  transaction_type, bsa_suspicious, bsa_reason, channel
) VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0020-7731'),
  SYSTIMESTAMP - INTERVAL '18' DAY, -4800.00, 'ABC ATM - Branch 001',
  'ATM_WITHDRAWAL', 'Y',
  'Cash withdrawal of $4,800 — just below $5,000 CTR reporting threshold. ' ||
  'Preceded by two similar transactions within 30 days. Possible structuring.',
  'ATM'
);
INSERT INTO abc.transactions (
  account_id, transaction_date, amount, merchant_name,
  transaction_type, bsa_suspicious, bsa_reason, channel, reference_number
) VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0020-7731'),
  SYSTIMESTAMP - INTERVAL '17' DAY, -1500.00, 'International Wire Transfer',
  'WIRE', 'Y',
  'International wire to unverified recipient account. Part of three-wire ' ||
  'sequence totalling $3,600 within 24 hours following large ATM withdrawal.',
  'WIRE', 'WIRE-2026-00441'
);
INSERT INTO abc.transactions (
  account_id, transaction_date, amount, merchant_name,
  transaction_type, bsa_suspicious, bsa_reason, channel, reference_number
) VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0020-7731'),
  SYSTIMESTAMP - INTERVAL '17' DAY, -1200.00, 'International Wire Transfer',
  'WIRE', 'Y',
  'International wire to unverified recipient account. Part of three-wire ' ||
  'sequence totalling $3,600 within 24 hours following large ATM withdrawal.',
  'WIRE', 'WIRE-2026-00442'
);
INSERT INTO abc.transactions (
  account_id, transaction_date, amount, merchant_name,
  transaction_type, bsa_suspicious, bsa_reason, channel, reference_number
) VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0020-7731'),
  SYSTIMESTAMP - INTERVAL '17' DAY, -900.00, 'International Wire Transfer',
  'WIRE', 'Y',
  'International wire to unverified recipient account. Part of three-wire ' ||
  'sequence totalling $3,600 within 24 hours following large ATM withdrawal.',
  'WIRE', 'WIRE-2026-00443'
);
INSERT INTO abc.transactions (
  account_id, transaction_date, amount, merchant_name,
  transaction_type, bsa_suspicious, bsa_reason, channel
) VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0020-7731'),
  SYSTIMESTAMP - INTERVAL '16' DAY, -4750.00, 'ABC ATM - Branch 002',
  'ATM_WITHDRAWAL', 'Y',
  'Second large ATM cash withdrawal ($4,750) from a different branch location ' ||
  'within 48 hours of prior $4,800 withdrawal and wire transfers. ' ||
  'Classic structuring pattern.',
  'ATM'
);

-- Bob: overdraft transactions
INSERT INTO abc.transactions (
  account_id, transaction_date, amount, merchant_name,
  transaction_type, fraud_flag, fraud_reason, channel
) VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0020-7731'),
  SYSTIMESTAMP - INTERVAL '5' DAY, -312.00, 'Jimenez Auto Parts',
  'PURCHASE', 'Y',
  'Transaction triggered overdraft. Second overdraft this month. ' ||
  'Flagged for potential account misuse review.',
  'ONLINE'
);
INSERT INTO abc.transactions (
  account_id, transaction_date, amount, merchant_name,
  transaction_type, channel
) VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0020-7731'),
  SYSTIMESTAMP - INTERVAL '2' DAY, -58.51, 'Shell Gas Station',
  'PURCHASE', 'MOBILE'
);
INSERT INTO abc.transactions (
  account_id, transaction_date, amount, merchant_name,
  transaction_type, channel
) VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0020-7731'),
  SYSTIMESTAMP - INTERVAL '1' DAY, 2800.00, 'Direct Deposit - Employer',
  'DEPOSIT', 'ONLINE'
);

-- Diana: premium normal transactions
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0030-2291'),
  SYSTIMESTAMP - INTERVAL '4' DAY, -8200.00, 'Porsche San Antonio', 'PURCHASE', 'BRANCH'
);
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0030-2291'),
  SYSTIMESTAMP - INTERVAL '8' DAY, -1847.32, 'Amex Card Payment', 'PAYMENT', 'ONLINE'
);
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0030-2291'),
  SYSTIMESTAMP - INTERVAL '10' DAY, 15000.00, 'Wire Transfer - Investment Account', 'WIRE', 'ONLINE'
);
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0030-2291'),
  SYSTIMESTAMP - INTERVAL '12' DAY, -4300.00, 'Republic of Texas Restaurant', 'PURCHASE', 'MOBILE'
);

-- Frank: loan payments missed, low activity
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'LOAN-0040-9902'),
  SYSTIMESTAMP - INTERVAL '91' DAY, -487.50, 'ABC Auto Loan Payment', 'PAYMENT', 'ONLINE'
);
-- Last payment was 91 days ago -- 90 days past due, collections triggered
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0040-9901'),
  SYSTIMESTAMP - INTERVAL '6' DAY, -43.22, 'Dollar General', 'PURCHASE', 'MOBILE'
);
INSERT INTO abc.transactions (account_id, transaction_date, amount, merchant_name, transaction_type, channel)
VALUES (
  (SELECT account_id FROM abc.accounts WHERE account_number = 'CHK-0040-9901'),
  SYSTIMESTAMP - INTERVAL '14' DAY, 850.00, 'Payroll Deposit', 'DEPOSIT', 'ONLINE'
);

COMMIT;

-- -----------------------------------------------------------------------------
-- SECTION 10: REP ASSIGNMENTS
-- -----------------------------------------------------------------------------

-- Rep Sarah: assigned to Alice and Bob
INSERT INTO abc.abc_rep_assignments (staff_id, customer_id, rep_email)
VALUES (
  (SELECT staff_id FROM abc.staff WHERE email = 'sarah.torres@abcbank.lab'),
  (SELECT customer_id FROM abc.customers WHERE email = 'alice.chen@abcbank.lab'),
  'sarah.torres@abcbank.lab'
);
INSERT INTO abc.abc_rep_assignments (staff_id, customer_id, rep_email)
VALUES (
  (SELECT staff_id FROM abc.staff WHERE email = 'sarah.torres@abcbank.lab'),
  (SELECT customer_id FROM abc.customers WHERE email = 'bob.martinez@abcbank.lab'),
  'sarah.torres@abcbank.lab'
);

-- Rep James: assigned to Diana and Frank
INSERT INTO abc.abc_rep_assignments (staff_id, customer_id, rep_email)
VALUES (
  (SELECT staff_id FROM abc.staff WHERE email = 'james.whitfield@abcbank.lab'),
  (SELECT customer_id FROM abc.customers WHERE email = 'diana.okafor@abcbank.lab'),
  'james.whitfield@abcbank.lab'
);
INSERT INTO abc.abc_rep_assignments (staff_id, customer_id, rep_email)
VALUES (
  (SELECT staff_id FROM abc.staff WHERE email = 'james.whitfield@abcbank.lab'),
  (SELECT customer_id FROM abc.customers WHERE email = 'frank.russo@abcbank.lab'),
  'james.whitfield@abcbank.lab'
);

COMMIT;

-- -----------------------------------------------------------------------------
-- SECTION 11: V_CUSTOMER_PORTAL VIEW
-- Single target for PAF SQL Query Node.
-- Deep Data Security row/column/cell policies apply here.
-- No joins needed in PAF agent -- everything is pre-joined.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW abc.v_customer_portal AS
SELECT
  -- Customer identity
  c.customer_id,
  c.first_name,
  c.last_name,
  c.ssn,                      -- DDS cell policy: masked to ***-**-XXXX for non-admin
  c.email,                    -- used as DDS identity anchor
  c.phone,
  c.customer_tier,
  c.account_status,
  c.collections_flag,
  c.branch_id,
  c.assigned_rep_id,

  -- Account details
  a.account_id,
  a.account_number,           -- DDS cell policy: masked to ****XXXX for non-admin
  a.account_type,
  a.balance,                  -- DDS column policy: NULL for AUDIT_USER
  a.credit_limit,
  a.status              AS account_status_detail,
  a.overdraft_count,
  a.opened_date,

  -- Transaction details
  t.transaction_id,
  t.transaction_date,
  t.amount,
  t.merchant_name,
  t.transaction_type,
  t.fraud_flag,
  t.fraud_reason,             -- DDS cell policy: NULL for customer role
  t.bsa_suspicious,
  t.bsa_reason,               -- DDS cell policy: NULL for customer and rep roles
  t.channel,
  t.reference_number,

  -- Credit card details
  cc.card_id,
  cc.card_number,             -- DDS cell policy: masked to ****-****-****-XXXX
  cc.card_type,
  cc.credit_limit       AS card_limit,
  cc.current_balance,         -- DDS column policy: NULL for AUDIT_USER
  cc.available_credit,
  cc.overlimit_flag,
  cc.overlimit_amount,
  cc.payment_due_date,
  cc.minimum_payment,
  cc.status             AS card_status

FROM abc.customers c
JOIN abc.accounts a
  ON a.customer_id = c.customer_id
JOIN abc.transactions t
  ON t.account_id = a.account_id
LEFT JOIN abc.credit_cards cc
  ON cc.customer_id = c.customer_id
WHERE t.transaction_date >= SYSTIMESTAMP - INTERVAL '180' DAY;

-- -----------------------------------------------------------------------------
-- SECTION 12: GRANTS
-- -----------------------------------------------------------------------------

-- Service account: SELECT on view only
GRANT SELECT ON abc.v_customer_portal TO abc_agent_svc;
GRANT SELECT ON abc.abc_rep_assignments TO abc_agent_svc;

-- Persona users: SELECT for direct SQLcl testing
GRANT SELECT ON abc.v_customer_portal   TO alice_chen, bob_martinez, diana_okafor,
                                           frank_russo, rep_sarah_torres,
                                           rep_james_whitfield, mgr_linda_chen,
                                           audit_user_abc;
GRANT SELECT ON abc.abc_rep_assignments TO rep_sarah_torres, rep_james_whitfield,
                                           mgr_linda_chen, audit_user_abc;

-- Synonyms so persona users can query without schema prefix
BEGIN
  FOR u IN (
    SELECT 'alice_chen' u FROM DUAL UNION ALL
    SELECT 'bob_martinez' FROM DUAL UNION ALL
    SELECT 'diana_okafor' FROM DUAL UNION ALL
    SELECT 'frank_russo' FROM DUAL UNION ALL
    SELECT 'rep_sarah_torres' FROM DUAL UNION ALL
    SELECT 'rep_james_whitfield' FROM DUAL UNION ALL
    SELECT 'mgr_linda_chen' FROM DUAL UNION ALL
    SELECT 'audit_user_abc' FROM DUAL
  ) LOOP
    EXECUTE IMMEDIATE
      'CREATE SYNONYM ' || u.u || '.v_customer_portal '||
      'FOR abc.v_customer_portal';
    EXECUTE IMMEDIATE
      'CREATE SYNONYM ' || u.u || '.abc_rep_assignments '||
      'FOR abc.abc_rep_assignments';
  END LOOP;
END;
/

COMMIT;

-- -----------------------------------------------------------------------------
-- SECTION 13: VERIFICATION QUERIES
-- Run these to confirm setup is correct before starting the lab
-- -----------------------------------------------------------------------------

-- Row counts
SELECT 'branches'           obj, COUNT(*) n FROM abc.branches         UNION ALL
SELECT 'staff'              obj, COUNT(*) n FROM abc.staff             UNION ALL
SELECT 'customers'          obj, COUNT(*) n FROM abc.customers         UNION ALL
SELECT 'accounts'           obj, COUNT(*) n FROM abc.accounts          UNION ALL
SELECT 'transactions'       obj, COUNT(*) n FROM abc.transactions      UNION ALL
SELECT 'credit_cards'       obj, COUNT(*) n FROM abc.credit_cards      UNION ALL
SELECT 'rep_assignments'    obj, COUNT(*) n FROM abc.abc_rep_assignments
ORDER BY 1;

-- Confirm view returns data
SELECT first_name, last_name, account_type, balance, bsa_suspicious
FROM abc.v_customer_portal
ORDER BY last_name, account_type;

-- Confirm BSA flags
SELECT first_name, last_name, transaction_date, amount, bsa_suspicious, bsa_reason
FROM abc.v_customer_portal
WHERE bsa_suspicious = 'Y'
ORDER BY transaction_date;

-- Confirm over-limit card
SELECT first_name, last_name, card_type, credit_limit, current_balance,
       overlimit_flag, overlimit_amount
FROM abc.v_customer_portal
WHERE overlimit_flag = 'Y';

-- Confirm collections flag
SELECT first_name, last_name, account_status, collections_flag
FROM abc.v_customer_portal
WHERE collections_flag = 'Y';

PROMPT
PROMPT ============================================================
PROMPT  ABC setup complete. Ready for Deep Data Security lab.
PROMPT  Run abc_dds_policies.sql in Phase 3.
PROMPT ============================================================
