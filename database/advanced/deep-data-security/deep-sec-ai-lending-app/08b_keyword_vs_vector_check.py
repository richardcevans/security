from array import array

from deal_db import object_name, run_for_user


query_vector = array("f", [0.05, 0.9, 0.05])

vector_sql = """
select title
from {loan_policies}
order by vector_distance(embedding, :query_vector, COSINE)
fetch first 3 rows only
""".format(loan_policies=object_name("loan_policies"))

keyword_sql = """
select title
from {loan_policies}
where lower(body) like :term
order by id
fetch first 3 rows only
""".format(loan_policies=object_name("loan_policies"))


def run_as(end_user):
    def work(conn):
        cur = conn.cursor()

        cur.execute(vector_sql, query_vector=query_vector)
        vector_titles = [row[0] for row in cur.fetchall()]

        cur.execute(keyword_sql, term="%credit risk%")
        keyword_titles = [row[0] for row in cur.fetchall()]

        return vector_titles, keyword_titles

    return run_for_user(end_user, work)


print("Optional vector-style vs keyword retrieval check")

for end_user in ["linda", "wendy"]:
    vector_titles, keyword_titles = run_as(end_user)
    print(f"\nAs {end_user}:")
    print(f"  Vector-style titles: {', '.join(vector_titles)}")
    print(
        "  Keyword titles for 'credit risk': "
        + (", ".join(keyword_titles) if keyword_titles else "none")
    )
