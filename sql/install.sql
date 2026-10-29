\set ON_ERROR_STOP on

begin;
\ir 01_schema.sql
\ir 02_data.sql
\ir 03_functions.sql
commit;

\ir 04_tests.sql
