from array import array

from deal_db import object_name, run_for_user


def _rows_as_dicts(cur):
    columns = [col[0].lower() for col in cur.description]
    return [dict(zip(columns, row)) for row in cur.fetchall()]


def _run_for_user(end_user, work):
    return run_for_user(end_user, work)


def _query_vector(query):
    text = query.lower()
    if "risk" in text or "credit" in text or "cash flow" in text:
        return array("f", [0.05, 0.9, 0.05])
    return array("f", [0.9, 0.1, 0.0])


def get_loan_applications(end_user):
    def work(conn):
        cur = conn.cursor()
        cur.execute(
            f"""
            select *
            from {object_name("loan_applications")}
            order by id
            """
        )
        return _rows_as_dicts(cur)

    return _run_for_user(end_user, work)


def get_application_detail(end_user, app_id):
    def work(conn):
        cur = conn.cursor()
        cur.execute(
            f"""
            select *
            from {object_name("loan_applications")}
            where id = :id
            """,
            id=app_id,
        )
        rows = _rows_as_dicts(cur)
        return rows[0] if rows else None

    return _run_for_user(end_user, work)


def search_policies(end_user, query):
    query_vector = _query_vector(query)

    def work(conn):
        cur = conn.cursor()
        cur.execute(
            f"""
            select id, title, body, audience,
                   vector_distance(embedding, :query_vector, COSINE) as distance
            from {object_name("loan_policies")}
            order by distance
            fetch first 3 rows only
            """,
            query_vector=query_vector,
        )
        return _rows_as_dicts(cur)

    return _run_for_user(end_user, work)
