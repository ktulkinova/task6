import pandas as pd
import streamlit as st
from db_code import fetch_batch

BATCH_SIZE = 10

st.set_page_config(page_title="Fake users", layout="wide")
st.title("Fake user generator")


LOCALES = {
    "Uzbekistan (uz_UZ)": "uz_UZ",
    "Kazakhstan (kk_KZ)": "kk_KZ",
}

col1, col2 = st.columns(2)
locale_label = col1.selectbox("Country", list(LOCALES))
seed = col2.number_input("Seed", min_value=0, value=42, step=1)
locale = LOCALES[locale_label]

params = (locale, int(seed))
if st.session_state.get("params") != params:
    st.session_state.params = params
    st.session_state.batch = 0

b1, b2 = st.columns(2)
if b1.button("Next batch"):
    st.session_state.batch += 1
if b2.button("Reset"):
    st.session_state.batch = 0

batch = st.session_state.batch

try:
    columns, rows = fetch_batch(locale, int(seed), batch)
except Exception as error:
    st.error(f"Database error: {error}")
    st.stop()

first = batch * BATCH_SIZE + 1
st.caption(f"Batch {batch}, users {first}-{first + BATCH_SIZE - 1}")
st.dataframe(pd.DataFrame(rows, columns=columns), hide_index=True, width="stretch")
