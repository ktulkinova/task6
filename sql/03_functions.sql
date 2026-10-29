create or replace function rnd(key text)
returns double precision
language sql immutable
as $$
    select (('x' || left(md5(key), 13))::bit(52)::bigint + 0.5) / 2 ^ 52
$$;

create or replace function rnd_key(locale text, seed bigint, batch integer, pos integer)
returns text
language sql immutable
as $$
    select concat_ws(':', locale, seed, batch, pos)
$$;

create or replace function rnd_int(key text, lo integer, hi integer)
returns integer
language sql immutable
as $$
    select lo + floor(rnd(key) * (hi - lo + 1))::integer
$$;

create or replace function rnd_normal(key text, mean double precision, sd double precision)
returns double precision
language sql immutable
as $$
    select mean + sd * sqrt(-2 * ln(rnd(key || ':u1'))) * cos(2 * pi() * rnd(key || ':u2'))
$$;

create or replace function rnd_lat(key text)
returns double precision
language sql immutable
as $$
    select degrees(asin(2 * rnd(key) - 1))
$$;

create or replace function rnd_lon(key text)
returns double precision
language sql immutable
as $$
    select 360 * rnd(key) - 180
$$;

create or replace function pick(locale text, kind text, key text)
returns text
language sql stable
as $$
    select value
    from names
    where locale = pick.locale
      and kind = pick.kind
      and idx = (select rnd_int(key, 0, n - 1)
                 from dict_size
                 where locale = pick.locale and kind = pick.kind)
$$;

create or replace function fill_mask(mask text, key text)
returns text
language sql immutable
as $$
    select string_agg(case when c = '#' then rnd_int(key || ':' || i, 0, 9)::text else c end,
                      '' order by i)
    from string_to_table(mask, null) with ordinality as t(c, i)
$$;

create or replace function sex(key text)
returns text
language sql immutable
as $$
    select case when rnd(key || ':sex') < 0.5 then 'male' else 'female' end
$$;

create or replace function first_name(locale text, key text, sex text)
returns text
language sql stable
as $$
    select pick(locale, 'first_' || sex, key || ':first')
$$;

create or replace function last_name(locale text, key text, sex text)
returns text
language sql stable
as $$
    select pick(locale, 'last_' || sex, key || ':last')
$$;

create or replace function patronymic(locale text, key text, sex text)
returns text
language sql stable
as $$
    select pick(locale, 'first_male', key || ':father') || ' '
        || pick(locale, 'patronymic_' || sex, key || ':patronymic')
$$;

create or replace function full_name(locale text, key text, sex text)
returns text
language sql stable
as $$
    select case rnd_int(key || ':name', 0, 3)
        when 0 then concat_ws(' ', f, l)
        when 1 then concat_ws(' ', pick(locale, 'title_' || sex, key || ':title'), f, l)
        when 2 then concat_ws(' ', l, f)
        else concat_ws(' ', l, f, patronymic(locale, key, sex))
    end
    from first_name(locale, key, sex) as f,
         last_name(locale, key, sex) as l
$$;

create or replace function address(locale text, key text)
returns text
language sql stable
as $$
    select case rnd_int(key || ':address', 0, 2)
        when 0 then format('%s, %s %s, %s-%s', city, street, sw, house, hw)
        when 1 then format('%s %s %s, %s', street, sw, house, city)
        else format('%s, %s %s, %s-%s, %s-%s', city, street, sw, house, hw, flat, aw)
    end
    from pick(locale, 'city', key || ':city') as city,
         pick(locale, 'street', key || ':street') as street,
         pick(locale, 'street_word', key || ':street_word') as sw,
         pick(locale, 'house_word', key || ':house_word') as hw,
         pick(locale, 'apartment_word', key || ':apartment_word') as aw,
         rnd_int(key || ':house', 1, 200) as house,
         rnd_int(key || ':flat', 1, 150) as flat
$$;

create or replace function phone(locale text, key text)
returns text
language sql stable
as $$
    select fill_mask(format(pick(locale, 'phone_format', key || ':phone_format'),
                            pick(locale, 'phone_country', key || ':phone_country'),
                            pick(locale, 'phone_operator', key || ':phone_operator')),
                     key || ':phone')
$$;

create or replace function email(locale text, key text, sex text)
returns text
language sql stable
as $$
    select regexp_replace(lower(case rnd_int(key || ':email', 0, 3)
               when 0 then f || '.' || l
               when 1 then l || '.' || f || rnd_int(key || ':email_num', 1, 99)
               when 2 then left(f, 1) || '.' || l || rnd_int(key || ':email_num', 1, 999)
               else f || l || rnd_int(key || ':email_num', 1970, 2008)
           end), '[^a-z0-9.]', '', 'g')
        || '@' || pick(locale, 'email_domain', key || ':email_domain')
    from first_name(locale, key, sex) as f,
         last_name(locale, key, sex) as l
$$;

create or replace function height_weight(key text, sex text, out height numeric, out weight numeric)
language sql immutable
as $$
    select round((p.h + p.hs * z1)::numeric, 1),
           round((p.w + p.ws * (0.5 * z1 + sqrt(0.75) * z2))::numeric, 1)
    from (values ('male', 176, 7, 76, 12), ('female', 163, 6.5, 62, 10)) as p(sex, h, hs, w, ws),
         rnd_normal(key || ':height', 0, 1) as z1,
         rnd_normal(key || ':weight', 0, 1) as z2
    where p.sex = height_weight.sex
$$;

create or replace function generate_users(locale text, seed bigint, batch integer, count integer default 10)
returns table (num bigint, name text, sex text, address text, latitude numeric, longitude numeric,
               height numeric, weight numeric, eye_color text, hair_color text, phone text, email text)
language sql stable
as $$
    select batch::bigint * count + pos + 1,
           full_name(locale, key, sex),
           sex,
           address(locale, key),
           round(rnd_lat(key || ':lat')::numeric, 5),
           round(rnd_lon(key || ':lon')::numeric, 5),
           hw.height,
           hw.weight,
           pick(locale, 'eye_color', key || ':eye_color'),
           pick(locale, 'hair_color', key || ':hair_color'),
           phone(locale, key),
           email(locale, key, sex)
    from generate_series(0, count - 1) as pos,
         rnd_key(locale, seed, batch, pos) as key,
         sex(key) as sex,
         height_weight(key, sex) as hw
    order by pos
$$;
