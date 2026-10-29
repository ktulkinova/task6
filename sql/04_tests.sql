with batches as (
    select l.locale, b.batch, u
    from unnest(array['uz_UZ', 'kk_KZ']) as l(locale),
         unnest(array[0, 1, 5]) as b(batch),
         generate_users(l.locale, 42, b.batch) as u
),
runs as (
    select r.id, string_agg(u::text, ';' order by u.num) as users
    from (values (1, 42, 0), (2, 42, 0), (3, 43, 0), (4, 42, 1)) as r(id, seed, batch),
         generate_users('uz_UZ', r.seed, r.batch) as u
    group by r.id
),
many as (
    select u.*
    from unnest(array['uz_UZ', 'kk_KZ']) as l(locale),
         generate_users(l.locale, 7, 0, 2000) as u
)
select 'batches with 10 rows' as test, count(*)::text as value, count(*) = 6 and bool_and(c = 10) as ok
from (select count(*) as c from batches group by locale, batch) as t
union all
select 'rows with null', count(*)::text, count(*) = 0
from batches where not (u is not null)
union all
select 'same arguments, same users', null, (select users from runs where id = 1) = (select users from runs where id = 2)
union all
select 'other seed, other users', null, (select users from runs where id = 1) <> (select users from runs where id = 3)
union all
select 'other batch, other users', null, (select users from runs where id = 1) <> (select users from runs where id = 4)
union all
select 'male height mean', round(avg(height), 1)::text, abs(avg(height) - 176) < 1
from many where sex = 'male'
union all
select 'female height mean', round(avg(height), 1)::text, abs(avg(height) - 163) < 1
from many where sex = 'female'
union all
select 'height and weight correlation', round(corr(height, weight)::numeric, 2)::text, abs(corr(height, weight) - 0.5) < 0.1
from many where sex = 'male'
union all
select 'share of abs(latitude) < 30', round(avg((abs(latitude) < 30)::integer), 3)::text,
       abs(avg((abs(latitude) < 30)::integer) - 0.5) < 0.03
from many
union all
select 'names with title', count(*)::text, count(*) > 0
from many where name ~ '^(Mr|Ms)\. '
union all
select 'names with patronymic', count(*)::text, count(*) > 0
from many where name ~ ' (o''g''li|qizi|uly|qyzy)$'
union all
select 'names without title and patronymic', count(*)::text, count(*) > 0
from many where name !~ '^(Mr|Ms)\. ' and name !~ ' (o''g''li|qizi|uly|qyzy)$'
union all
select 'emails with apostrophe', count(*)::text, count(*) = 0
from many where email like '%''%'
union all
select 'emails with other characters', count(*)::text, count(*) = 0
from many where email !~ '^[a-z0-9.]+@[a-z0-9.]+$'
union all
select 'dictionaries with gaps in idx', count(*)::text, count(*) = 0
from (select locale, kind from names group by locale, kind having min(idx) <> 0 or max(idx) <> count(*) - 1) as t
union all
select 'wrong dict_size rows', count(*)::text, count(*) = 0
from (select locale, kind, count(*) as n from names group by locale, kind) as t
full join dict_size as d using (locale, kind)
where t.n is distinct from d.n;
