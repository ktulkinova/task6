begin;

create table if not exists email_domains (
    id integer generated always as identity primary key,
    locale_code varchar(10) not null references locales (locale_code),
    domain_name text not null,
    unique (locale_code, domain_name)
);

insert into email_domains (locale_code, domain_name)
values
    ('uz_UZ', 'gmail.com'),
    ('uz_UZ', 'icloud.com'),
    ('uz_UZ', 'outlook.com'),
    ('uz_UZ', 'mail.ru'),
    ('uz_UZ', 'umail.uz'),
    ('kk_KZ', 'gmail.com'),
    ('kk_KZ', 'icloud.com'),
    ('kk_KZ', 'outlook.com'),
    ('kk_KZ', 'mail.ru'),
    ('kk_KZ', 'mail.kz')
on conflict (locale_code, domain_name) do nothing;

update first_names
set name = 'No''mon'
where locale_code = 'uz_UZ'
  and name = 'No''''mon';

drop procedure if exists generate_attributes(text, bigint, integer, integer);

create or replace procedure random_uniform(
    p_locale text,
    p_seed bigint,
    p_batch integer,
    p_position integer,
    p_field text,
    out result double precision
)
language plpgsql
as $$
declare
    hash_value text;
    number_value bigint;
begin
    hash_value := md5(
        json_build_array(p_locale, p_seed, p_batch, p_position, p_field)::text
    );

    number_value := ('x' || substr(hash_value, 1, 13))::bit(52)::bigint;

    result := (number_value + 0.5) / 4503599627370496.0;
end;
$$;

create or replace procedure random_integer(
    p_locale text,
    p_seed bigint,
    p_batch integer,
    p_position integer,
    p_field text,
    p_min integer,
    p_max integer,
    out result integer
)
language plpgsql
as $$
declare
    random_value double precision;
begin
    if p_min is null or p_max is null or p_min > p_max then
        raise exception 'Invalid range: min and max are required, min must be <= max';
    end if;

    call random_uniform(
        p_locale, p_seed, p_batch, p_position,
        p_field, random_value
    );

    result := (
        p_min::bigint
        + floor(
            random_value * (p_max::bigint - p_min::bigint + 1)
        )::bigint
    )::integer;
end;
$$;

create or replace procedure random_normal(
    p_locale text,
    p_seed bigint,
    p_batch integer,
    p_position integer,
    p_field text,
    p_mean double precision,
    p_stddev double precision,
    out result double precision
)
language plpgsql
as $$
declare
    u1 double precision;
    u2 double precision;
    z double precision;
begin
    if p_mean is null or p_stddev is null or p_stddev < 0 then
        raise exception 'Mean is required; standard deviation must be non-negative';
    end if;

    call random_uniform(
        p_locale, p_seed, p_batch, p_position,
        p_field || '_u1', u1
    );

    call random_uniform(
        p_locale, p_seed, p_batch, p_position,
        p_field || '_u2', u2
    );

    z := sqrt(-2.0 * ln(u1)) * cos(2.0 * pi() * u2);

    result := p_mean + p_stddev * z;
end;
$$;

create or replace procedure generate_name(
    p_locale text,
    p_seed bigint,
    p_batch integer,
    p_position integer,
    out name text,
    out sex text
)
language plpgsql
as $$
declare
    choice integer;
    items_count integer;
    selected_first_name text;
    selected_last_name text;
    selected_title text;
begin
    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'gender', 0, 1, choice
    );

    if choice = 0 then
        sex := 'female';
    else
        sex := 'male';
    end if;

    select count(*) into items_count
    from first_names as f
    where f.locale_code = p_locale
      and f.gender = sex;

    if items_count = 0 then
        raise exception 'No first names for locale % and sex %',
            p_locale, sex;
    end if;

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'first_name', 0, items_count - 1, choice
    );

    select f.name into selected_first_name
    from first_names as f
    where f.locale_code = p_locale
      and f.gender = sex
    order by f.id
    limit 1 offset choice;

    select count(*) into items_count
    from last_names as l
    where l.locale_code = p_locale
      and l.gender = sex;

    if items_count = 0 then
        raise exception 'No last names for locale % and sex %',
            p_locale, sex;
    end if;

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'last_name', 0, items_count - 1, choice
    );

    select l.surname into selected_last_name
    from last_names as l
    where l.locale_code = p_locale
      and l.gender = sex
    order by l.id
    limit 1 offset choice;

    name := selected_first_name || ' ' || selected_last_name;

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'use_title', 0, 1, choice
    );

    if choice = 1 then
        select count(*) into items_count
        from titles as t
        where t.locale_code = p_locale
          and t.gender = sex;

        if items_count > 0 then
            call random_integer(
                p_locale, p_seed, p_batch, p_position,
                'title', 0, items_count - 1, choice
            );

            select t.title into selected_title
            from titles as t
            where t.locale_code = p_locale
              and t.gender = sex
            order by t.id
            limit 1 offset choice;

            name := selected_title || ' ' || name;
        end if;
    end if;
end;
$$;

create or replace procedure generate_address(
    p_locale text,
    p_seed bigint,
    p_batch integer,
    p_position integer,
    out address text
)
language plpgsql
as $$
declare
    choice integer;
    items_count integer;
    selected_city text;
    selected_street text;
    v_street_word text;
    v_house_word text;
    v_apartment_word text;
    house_number integer;
    apartment_number integer;
    street_part text;
    house_part text;
begin
    select l.street_word, l.house_word, l.apartment_word
    into v_street_word, v_house_word, v_apartment_word
    from locales as l
    where l.locale_code = p_locale;

    select count(*) into items_count
    from cities as c
    where c.locale_code = p_locale;

    if items_count = 0 then
        raise exception 'No cities for locale %', p_locale;
    end if;

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'city', 0, items_count - 1, choice
    );

    select c.city_name into selected_city
    from cities as c
    where c.locale_code = p_locale
    order by c.id
    limit 1 offset choice;

    select count(*) into items_count
    from street_names as s
    where s.locale_code = p_locale;

    if items_count = 0 then
        raise exception 'No streets for locale %', p_locale;
    end if;

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'street', 0, items_count - 1, choice
    );

    select s.street_name into selected_street
    from street_names as s
    where s.locale_code = p_locale
    order by s.id
    limit 1 offset choice;

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'house_number', 1, 200, house_number
    );

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'apartment_number', 1, 150, apartment_number
    );

    street_part := concat_ws(' ', selected_street, v_street_word);
    house_part := house_number::text
        || coalesce('-' || v_house_word, '');

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'address_format', 0, 2, choice
    );

    if choice = 0 then
        address := selected_city || ', ' || street_part || ', ' || house_part;
    elsif choice = 1 then
        address := street_part || ' ' || house_number || ', ' || selected_city;
    else
        address := selected_city || ', ' || street_part || ', ' || house_part
            || ', ' || apartment_number
            || coalesce('-' || v_apartment_word, '');
    end if;
end;
$$;

create or replace procedure generate_phone(
    p_locale text,
    p_seed bigint,
    p_batch integer,
    p_position integer,
    out phone text
)
language plpgsql
as $$
declare
    selected_country_code text;
    selected_operator_code text;
    items_count integer;
    choice integer;
    subscriber_number integer;
    digits text;
    format_choice integer;
begin
    select s.country_code, s.operator_code
    into selected_country_code, selected_operator_code
    from phone_settings as s
    where s.locale_code = p_locale;

    if not found then
        raise exception 'No phone settings for locale %', p_locale;
    end if;

    select count(*) into items_count
    from phone_operators as o
    where o.locale_code = p_locale;

    if items_count > 0 then
        call random_integer(
            p_locale, p_seed, p_batch, p_position,
            'phone_operator', 0, items_count - 1, choice
        );

        select o.operator_code into selected_operator_code
        from phone_operators as o
        where o.locale_code = p_locale
        order by o.id
        limit 1 offset choice;
    end if;

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'phone_number', 0, 9999999, subscriber_number
    );

    digits := lpad(subscriber_number::text, 7, '0');

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'phone_format', 0, 2, format_choice
    );

    if format_choice = 0 then
        phone := '+' || selected_country_code
            || selected_operator_code || digits;
    elsif format_choice = 1 then
        phone := '+' || selected_country_code || ' '
            || selected_operator_code || ' '
            || substr(digits, 1, 3) || '-'
            || substr(digits, 4, 2) || '-'
            || substr(digits, 6, 2);
    else
        phone := '+' || selected_country_code || ' ('
            || selected_operator_code || ') '
            || substr(digits, 1, 3) || ' '
            || substr(digits, 4, 2) || ' '
            || substr(digits, 6, 2);
    end if;
end;
$$;

create or replace procedure generate_email(
    p_locale text,
    p_seed bigint,
    p_batch integer,
    p_position integer,
    out email text
)
language plpgsql
as $$
declare
    person_name text;
    person_sex text;
    first_name text;
    last_name text;
    email_name text;
    number_suffix integer;
    items_count integer;
    choice integer;
    email_domain text;
begin
    call generate_name(
        p_locale, p_seed, p_batch, p_position,
        person_name, person_sex
    );

    first_name := split_part(person_name, ' ', -2);
    last_name := split_part(person_name, ' ', -1);
    email_name := lower(first_name || '.' || last_name);
    email_name := regexp_replace(email_name, '[^a-z0-9.]', '', 'g');

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'email_suffix', 100, 999, number_suffix
    );

    select count(*) into items_count
    from email_domains as d
    where d.locale_code = p_locale;

    if items_count = 0 then
        raise exception 'No email domains for locale %', p_locale;
    end if;

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'email_domain', 0, items_count - 1, choice
    );

    select d.domain_name into email_domain
    from email_domains as d
    where d.locale_code = p_locale
    order by d.id
    limit 1 offset choice;

    email := email_name || number_suffix || '@' || email_domain;
end;
$$;

commit;
