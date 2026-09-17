# Copyright (c) 2026, Oracle and/or its affiliates.
"""Unit tests for the MCP read-only SQL boundary."""

import unittest

from oracle_sql_mcp.sql import bounded_limit, clean_read_only_sql


class SqlGuardTests(unittest.TestCase):
    def test_allows_read_only_statements_and_one_terminator(self):
        for statement in (
            "SELECT 1",
            "SELECT 1;",
            "WITH x AS (SELECT 1 FROM dual) SELECT * FROM x",
            "EXPLAIN PLAN FOR SELECT 1 FROM dual",
        ):
            with self.subTest(statement=statement):
                self.assertTrue(clean_read_only_sql(statement))

    def test_rejects_writes_comments_and_multiple_terminators(self):
        for statement in (
            "UPDATE employees SET salary = 1",
            "SELECT 1 -- comment",
            "SELECT 1; SELECT 2",
            "SELECT 1;;",
            "",
        ):
            with self.subTest(statement=statement):
                with self.assertRaises(ValueError):
                    clean_read_only_sql(statement)

    def test_bounded_limit(self):
        self.assertEqual(bounded_limit(0), 1)
        self.assertEqual(bounded_limit(25), 25)
        self.assertEqual(bounded_limit(999), 500)


if __name__ == "__main__":
    unittest.main()
