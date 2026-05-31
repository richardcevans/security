from array import array

from deal_db import object_name, run_for_user


query_text = "unstable cash flow or credit risk"
query_vector = array("f", [0.05, 0.9, 0.05])

sql = """
select id, title, audience,
       vector_distance(embedding, :query_vector, COSINE) as distance
from {loan_policies}
order by distance
fetch first 3 rows only
""".format(loan_policies=object_name("loan_policies"))


def search_as(end_user):
    def work(conn):
        cur = conn.cursor()
        cur.execute(sql, query_vector=query_vector)
        return cur.fetchall()

    return run_for_user(end_user, work)


print("Deep Sec-scoped vector retrieval demo")
print(f"Policy search query: {query_text}")
print("Output below is scoped by the active Deep Sec end user.")

for end_user in ["linda", "wendy"]:
    print(f"\nAs {end_user}:")
    for index, row in enumerate(search_as(end_user), start=1):
        print(f"  {index}. {row[1]:<35} distance: {row[3]:.6f}")
