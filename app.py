import os

import psycopg
from flask import Flask, render_template, request
from psycopg.rows import dict_row

app = Flask(__name__)


@app.route("/")
def index():
    locale = request.args.get("locale", "uz_UZ")
    seed = request.args.get("seed", 42, type=int)
    page = max(request.args.get("page", 0, type=int), 0)

    with psycopg.connect(os.environ["DATABASE_URL"], row_factory=dict_row) as conn:
        countries = conn.execute(
            "select locale, value as country from names where kind = 'country' order by value"
        ).fetchall()
        users = conn.execute(
            "select * from generate_users(%s, %s, %s)", (locale, seed, page)
        ).fetchall()

    return render_template(
        "index.html",
        countries=countries,
        users=users,
        locale=locale,
        seed=seed,
        page=page,
    )
