from array import array

from deal_db import object_name, run_for_user


query_vector = array("f", [0.9, 0.1, 0.0])

sql = """
select title,
       vector_distance(embedding, :query_vector, COSINE) as distance
from {loan_policies}
order by distance
fetch first 3 rows only
""".format(loan_policies=object_name("loan_policies"))

print("Vector warm-up with manual 3-dimensional vectors")
print("Vector warm-up user context: linda")
print(f"Query vector: {list(query_vector)}")

def work(conn):
    cur = conn.cursor()
    cur.execute(sql, query_vector=query_vector)

    print("\nNearest policy vectors:")
    for index, (title, distance) in enumerate(cur, start=1):
        print(f"{index}. {title:<35} distance: {distance:.6f}")


run_for_user("linda", work)
