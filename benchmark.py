import os
import time

import psycopg

SIZES = [1000, 10000, 100000]

with psycopg.connect(os.environ["DATABASE_URL"]) as conn:
    conn.execute("select count(*) from generate_users('uz_UZ', 1, 0, 100)")
    for locale in ["uz_UZ", "kk_KZ"]:
        for size in SIZES:
            start = time.perf_counter()
            conn.execute("select count(*) from generate_users(%s, 42, 0, %s)", (locale, size)).fetchone()
            seconds = time.perf_counter() - start
            print(f"{locale}  {size:>7} users  {seconds:7.2f} s  {size / seconds:9.0f} users/s")
