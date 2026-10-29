import os

import psycopg2


def get_connection():
    database_url = os.getenv("DATABASE_URL")
    if database_url:
        return psycopg2.connect(database_url)

    return psycopg2.connect(
        dbname=os.getenv("PGDATABASE", "fake_users"),
        user=os.getenv("PGUSER", "postgres"),
        password=os.getenv("PGPASSWORD"),
        host=os.getenv("PGHOST", "localhost"),
        port=int(os.getenv("PGPORT", "5432")),
    )


def fetch_batch(locale, seed, batch_index):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL generate_batch(%s::text, %s::bigint, %s::integer);",
                (locale, seed, batch_index),
            )
            cur.execute("SELECT * FROM generated_users ORDER BY position;")
            columns = [col[0] for col in cur.description]
            rows = cur.fetchall()
        return columns, rows
    finally:
        conn.close()


if __name__ == "__main__":
    columns, rows = fetch_batch("uz_UZ", 42, 0)
    print(columns)
    for row in rows:
        print(row)
