--
-- PostgreSQL database dump
--

\restrict ZLQL3as6BKuPjhp9dk2qQn0nZd8XuJbtkcPOCwAVCuYtjrIrZ1jxt1YogAjt8Xq

-- Dumped from database version 18.3 (Homebrew)
-- Dumped by pg_dump version 18.3 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: generate_address(text, bigint, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_address(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, OUT address text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: generate_attributes(text, bigint, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_attributes(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, IN p_sex text, OUT height_cm numeric, OUT weight_kg numeric, OUT hair_color text)
    LANGUAGE plpgsql
    AS $$
declare
    height_mean double precision;
    height_stddev double precision;
    weight_mean double precision;
    weight_stddev double precision;
    height_z double precision;
    weight_z_independent double precision;
    generated_height double precision;
    generated_weight double precision;
    items_count integer;
    choice integer;
begin
    if p_sex = 'male' then
        height_mean := 176;
        height_stddev := 7;
        weight_mean := 76;
        weight_stddev := 12;
    elsif p_sex = 'female' then
        height_mean := 163;
        height_stddev := 6.5;
        weight_mean := 62;
        weight_stddev := 10;
    else
        raise exception 'Sex must be male or female';
    end if;

    call random_normal(
        p_locale, p_seed, p_batch, p_position,
        'height_z', 0, 1, height_z
    );

    call random_normal(
        p_locale, p_seed, p_batch, p_position,
        'weight_z', 0, 1, weight_z_independent
    );

    generated_height := height_mean + height_stddev * height_z;

    generated_weight := weight_mean
        + weight_stddev * (
            0.55 * height_z
            + sqrt(1 - 0.55 * 0.55) * weight_z_independent
        );

    height_cm := round(generated_height::numeric, 1);
    weight_kg := round(generated_weight::numeric, 1);

    select count(*) into items_count
    from hair_colors as h
    where h.locale_code = p_locale;

    if items_count = 0 then
        raise exception 'No hair colors for locale %', p_locale;
    end if;

    call random_integer(
        p_locale, p_seed, p_batch, p_position,
        'hair_color', 0, items_count - 1, choice
    );

    select h.color_name into hair_color
    from hair_colors as h
    where h.locale_code = p_locale
    order by h.id
    limit 1 offset choice;
end;
$$;


--
-- Name: generate_batch(text, bigint, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_batch(IN p_locale text, IN p_seed bigint, IN p_batch integer)
    LANGUAGE plpgsql
    AS $$
declare
    i integer;
    v_name text;
    v_sex text;
    v_address text;
    v_latitude double precision;
    v_longitude double precision;
    v_height numeric;
    v_weight numeric;
    v_hair_color text;
    v_phone text;
    v_email text;
begin
    if p_seed is null then
        raise exception 'Seed is required';
    end if;

    if p_batch is null or p_batch < 0 then
        raise exception 'Batch index must be zero or greater';
    end if;

    if not exists (
        select 1
        from locales
        where locale_code = p_locale
    ) then
        raise exception 'Unknown locale: %', p_locale;
    end if;

    create temporary table if not exists generated_users (
        position integer primary key,
        name text,
        sex text,
        address text,
        latitude double precision,
        longitude double precision,
        height_cm numeric,
        weight_kg numeric,
        hair_color text,
        phone text,
        email text
    );

    truncate table pg_temp.generated_users;

    for i in 0..9 loop
        call generate_user(
            p_locale, p_seed, p_batch, i,
            v_name, v_sex, v_address,
            v_latitude, v_longitude,
            v_height, v_weight, v_hair_color,
            v_phone, v_email
        );

        insert into pg_temp.generated_users (
            position, name, sex, address,
            latitude, longitude,
            height_cm, weight_kg, hair_color,
            phone, email
        )
        values (
            i, v_name, v_sex, v_address,
            v_latitude, v_longitude,
            v_height, v_weight, v_hair_color,
            v_phone, v_email
        );
    end loop;
end;
$$;


--
-- Name: generate_coordinates(text, bigint, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_coordinates(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, OUT latitude double precision, OUT longitude double precision)
    LANGUAGE plpgsql
    AS $$
declare
    u double precision;
    v double precision;
begin
    call random_uniform(
        p_locale, p_seed, p_batch, p_position,
        'latitude', u
    );

    call random_uniform(
        p_locale, p_seed, p_batch, p_position,
        'longitude', v
    );

    latitude := degrees(asin(2.0 * u - 1.0));
    longitude := 360.0 * v - 180.0;
end;
$$;


--
-- Name: generate_email(text, bigint, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_email(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, OUT email text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: generate_name(text, bigint, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_name(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, OUT name text, OUT sex text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: generate_phone(text, bigint, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_phone(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, OUT phone text)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: generate_user(text, bigint, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_user(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, OUT name text, OUT sex text, OUT address text, OUT latitude double precision, OUT longitude double precision, OUT height_cm numeric, OUT weight_kg numeric, OUT hair_color text, OUT phone text, OUT email text)
    LANGUAGE plpgsql
    AS $$
begin
    call generate_name(
        p_locale, p_seed, p_batch, p_position,
        name, sex
    );

    call generate_address(
        p_locale, p_seed, p_batch, p_position,
        address
    );

    call generate_coordinates(
        p_locale, p_seed, p_batch, p_position,
        latitude, longitude
    );

    call generate_attributes(
        p_locale, p_seed, p_batch, p_position, sex,
        height_cm, weight_kg, hair_color
    );

    call generate_phone(
        p_locale, p_seed, p_batch, p_position,
        phone
    );

    call generate_email(
        p_locale, p_seed, p_batch, p_position,
        email
    );
end;
$$;


--
-- Name: random_integer(text, bigint, integer, integer, text, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.random_integer(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, IN p_field text, IN p_min integer, IN p_max integer, OUT result integer)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: random_normal(text, bigint, integer, integer, text, double precision, double precision); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.random_normal(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, IN p_field text, IN p_mean double precision, IN p_stddev double precision, OUT result double precision)
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: random_uniform(text, bigint, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.random_uniform(IN p_locale text, IN p_seed bigint, IN p_batch integer, IN p_position integer, IN p_field text, OUT result double precision)
    LANGUAGE plpgsql
    AS $$
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cities (
    id integer NOT NULL,
    locale_code character varying(10) NOT NULL,
    city_name text NOT NULL
);


--
-- Name: cities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.cities ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.cities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: email_domains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_domains (
    id integer NOT NULL,
    locale_code character varying(10) NOT NULL,
    domain_name text NOT NULL
);


--
-- Name: email_domains_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.email_domains ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.email_domains_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: first_names; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.first_names (
    id integer NOT NULL,
    locale_code character varying(10) NOT NULL,
    name text NOT NULL,
    gender text NOT NULL,
    CONSTRAINT first_names_gender_check CHECK ((gender = ANY (ARRAY['female'::text, 'male'::text])))
);


--
-- Name: first_names_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.first_names ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.first_names_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: hair_colors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hair_colors (
    id integer NOT NULL,
    locale_code character varying(10) NOT NULL,
    color_name text NOT NULL
);


--
-- Name: hair_colors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.hair_colors ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.hair_colors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: last_names; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.last_names (
    id integer NOT NULL,
    locale_code character varying(10) NOT NULL,
    surname text NOT NULL,
    gender text NOT NULL,
    CONSTRAINT last_names_gender_check CHECK ((gender = ANY (ARRAY['female'::text, 'male'::text])))
);


--
-- Name: last_names_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.last_names ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.last_names_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: locales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.locales (
    locale_code character varying(10) NOT NULL,
    locale_name text NOT NULL,
    street_word text NOT NULL,
    house_word text,
    apartment_word text
);


--
-- Name: phone_operators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.phone_operators (
    id integer NOT NULL,
    locale_code character varying(10) NOT NULL,
    operator_code text NOT NULL
);


--
-- Name: phone_operators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.phone_operators ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phone_operators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: phone_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.phone_settings (
    locale_code character varying(10) NOT NULL,
    country_code text NOT NULL,
    operator_code text NOT NULL
);


--
-- Name: street_names; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.street_names (
    id integer NOT NULL,
    locale_code character varying(10) NOT NULL,
    street_name text NOT NULL
);


--
-- Name: street_names_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.street_names ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.street_names_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: titles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.titles (
    id integer NOT NULL,
    locale_code character varying(10) NOT NULL,
    title text NOT NULL,
    gender text NOT NULL,
    CONSTRAINT titles_gender_check CHECK ((gender = ANY (ARRAY['female'::text, 'male'::text])))
);


--
-- Name: titles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.titles ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.titles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Data for Name: cities; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cities (id, locale_code, city_name) FROM stdin;
1	uz_UZ	Tashkent
2	uz_UZ	Samarkand
3	uz_UZ	Bukhara
4	kk_KZ	Almaty
5	kk_KZ	Astana
6	kk_KZ	Shymkent
10	uz_UZ	Andijan
11	uz_UZ	Namangan
12	uz_UZ	Fergana
13	uz_UZ	Nukus
14	uz_UZ	Urgench
15	uz_UZ	Khiva
16	uz_UZ	Qarshi
17	uz_UZ	Termez
18	uz_UZ	Navoi
19	uz_UZ	Jizzakh
20	uz_UZ	Gulistan
21	uz_UZ	Kokand
22	uz_UZ	Margilan
23	uz_UZ	Shahrisabz
24	uz_UZ	Chirchiq
25	uz_UZ	Angren
26	uz_UZ	Almalyk
27	uz_UZ	Bekabad
28	uz_UZ	Yangiyul
29	uz_UZ	Kattaqo'rg'on
30	uz_UZ	Gijduvon
31	uz_UZ	Zarafshan
32	uz_UZ	Uchquduq
33	uz_UZ	Nurota
34	uz_UZ	Denov
35	uz_UZ	Boysun
36	uz_UZ	Sherobod
37	uz_UZ	Chust
38	uz_UZ	Kosonsoy
39	uz_UZ	Rishton
40	uz_UZ	Quvasoy
41	uz_UZ	Asaka
42	uz_UZ	Shahrixon
43	uz_UZ	Beruniy
44	uz_UZ	Turtkul
45	uz_UZ	Chimboy
46	uz_UZ	Moynaq
50	kk_KZ	Karaganda
51	kk_KZ	Aktobe
52	kk_KZ	Taraz
53	kk_KZ	Pavlodar
54	kk_KZ	Oskemen
55	kk_KZ	Semey
56	kk_KZ	Atyrau
57	kk_KZ	Kostanay
58	kk_KZ	Kyzylorda
59	kk_KZ	Oral
60	kk_KZ	Petropavl
61	kk_KZ	Aktau
62	kk_KZ	Turkistan
63	kk_KZ	Kokshetau
64	kk_KZ	Temirtau
65	kk_KZ	Taldykorgan
66	kk_KZ	Ekibastuz
67	kk_KZ	Rudny
68	kk_KZ	Zhezkazgan
69	kk_KZ	Balkhash
70	kk_KZ	Satpayev
71	kk_KZ	Kaskelen
72	kk_KZ	Kentau
73	kk_KZ	Ridder
74	kk_KZ	Stepnogorsk
75	kk_KZ	Aksu
76	kk_KZ	Saran
77	kk_KZ	Shakhtinsk
78	kk_KZ	Arys
79	kk_KZ	Baikonur
80	kk_KZ	Zhanaozen
81	kk_KZ	Talgar
82	kk_KZ	Qonaev
83	kk_KZ	Shchuchinsk
84	kk_KZ	Esik
85	kk_KZ	Atbasar
86	kk_KZ	Zhetysai
\.


--
-- Data for Name: email_domains; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.email_domains (id, locale_code, domain_name) FROM stdin;
1	uz_UZ	gmail.com
2	uz_UZ	icloud.com
3	uz_UZ	outlook.com
4	uz_UZ	mail.ru
5	uz_UZ	umail.uz
6	kk_KZ	gmail.com
7	kk_KZ	icloud.com
8	kk_KZ	outlook.com
9	kk_KZ	mail.ru
10	kk_KZ	mail.kz
\.


--
-- Data for Name: first_names; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.first_names (id, locale_code, name, gender) FROM stdin;
1	uz_UZ	Aziz	male
2	uz_UZ	Kamola	female
3	uz_UZ	Sardor	male
4	uz_UZ	Malika	female
5	kk_KZ	Alikhan	male
6	kk_KZ	Aiaru	female
7	kk_KZ	Yerlan	male
8	kk_KZ	Aruzhan	female
9	kk_KZ	Abai	male
10	kk_KZ	Abaidildan	male
11	kk_KZ	Abakan	male
12	kk_KZ	Abbas	male
13	kk_KZ	Abdan	male
14	kk_KZ	Abdesh	male
15	kk_KZ	Abdi	male
16	kk_KZ	Abdibai	male
17	kk_KZ	Abdigali	male
18	kk_KZ	Abdigazy	male
19	kk_KZ	Abdik	male
20	kk_KZ	Abdikadyr	male
21	kk_KZ	Abdikarim	male
22	kk_KZ	Abdiken	male
23	kk_KZ	Abdikhalyk	male
24	kk_KZ	Abdilda	male
25	kk_KZ	Abdimanap	male
26	kk_KZ	Abdir	male
27	kk_KZ	Abdiraiym	male
28	kk_KZ	Abdirak	male
29	kk_KZ	Abdirakhman	male
30	kk_KZ	Abdirali	male
31	kk_KZ	Abdirash	male
32	kk_KZ	Abdirashit	male
33	kk_KZ	Abdirazak	male
34	kk_KZ	Abdirei	male
35	kk_KZ	Abdissattar	male
36	kk_KZ	Abdizhamil	male
37	kk_KZ	Abdizhappar	male
38	kk_KZ	Abdol	male
39	kk_KZ	Abdolla	male
40	kk_KZ	Abduali	male
41	kk_KZ	Abebai	male
42	kk_KZ	Aben	male
43	kk_KZ	Abet	male
44	kk_KZ	Abeu	male
45	kk_KZ	Abiba	female
46	kk_KZ	Abibolla	male
47	kk_KZ	Abikan	male
48	kk_KZ	Abiken	male
49	kk_KZ	Abil	male
50	kk_KZ	Abilbek	male
51	kk_KZ	Abilgaziz	male
52	kk_KZ	Abilgazy	male
53	kk_KZ	Abilkai	male
54	kk_KZ	Abilkaiyr	male
55	kk_KZ	Abilkan	male
56	kk_KZ	Abilkassym	male
57	kk_KZ	Abilzhan	male
58	kk_KZ	Abira	female
59	kk_KZ	Abish	male
60	kk_KZ	Ablak	male
61	kk_KZ	Absalam	male
62	kk_KZ	Absalim	male
63	kk_KZ	Absamat	male
64	kk_KZ	Abseiit	male
65	kk_KZ	Abu	male
66	kk_KZ	Abubakir	male
67	kk_KZ	Abugali	male
68	kk_KZ	Abukhamit	male
69	kk_KZ	Abukhan	male
70	kk_KZ	Abunassyr	male
71	kk_KZ	Abussadyk	male
72	kk_KZ	Abusseiit	male
73	kk_KZ	Abuzar	male
74	kk_KZ	Abylai	male
75	kk_KZ	Abylgazy	male
76	kk_KZ	Abyz	male
77	kk_KZ	Abzal	male
78	kk_KZ	Abzhami	male
79	kk_KZ	Abzhan	male
80	kk_KZ	Ada	female
81	kk_KZ	Adai	male
82	kk_KZ	Adaikhan	male
83	kk_KZ	Adam	male
84	kk_KZ	Adambai	male
85	kk_KZ	Adambek	male
86	kk_KZ	Adeliya	female
87	kk_KZ	Ademi	female
88	kk_KZ	Adi	male
89	kk_KZ	Adiba	female
90	kk_KZ	Adibai	male
91	kk_KZ	Adida	female
92	kk_KZ	Adiet	male
93	kk_KZ	Adikan	male
94	kk_KZ	Adil	male
95	kk_KZ	Adila	female
96	kk_KZ	Adilbek	male
97	kk_KZ	Adilgazy	male
98	kk_KZ	Adiliya	female
99	kk_KZ	Adilkhan	male
100	kk_KZ	Adilshi	male
101	kk_KZ	Adilzhan	male
102	kk_KZ	Adina	female
103	kk_KZ	Adipa	female
104	kk_KZ	Adirbek	male
105	kk_KZ	Adissa	female
106	kk_KZ	Adiya	female
107	kk_KZ	Adliya	female
108	kk_KZ	Adyrbai	male
109	kk_KZ	Aelita	female
110	kk_KZ	Agabek	male
111	kk_KZ	Agadil	male
112	kk_KZ	Agaisha	female
113	kk_KZ	Agamaly	male
114	kk_KZ	Agedil	male
115	kk_KZ	Agila	female
116	kk_KZ	Agipa	female
117	kk_KZ	Agliya	female
118	kk_KZ	Agybai	male
119	kk_KZ	Agyman	male
120	kk_KZ	Agyn	male
121	kk_KZ	Agzam	male
122	kk_KZ	Aiadil	male
123	kk_KZ	Aiassem	female
124	kk_KZ	Aibader	female
125	kk_KZ	Aibakan	male
126	kk_KZ	Aibanat	female
127	kk_KZ	Aibanu	female
128	kk_KZ	Aibar	male
129	kk_KZ	Aibarsha	female
130	kk_KZ	Aibarshyn	female
131	kk_KZ	Aibas	male
132	kk_KZ	Aibat	male
133	kk_KZ	Aibates	female
134	kk_KZ	Aibeinesh	female
135	kk_KZ	Aibek	male
136	kk_KZ	Aiberdi	male
137	kk_KZ	Aibergen	male
138	kk_KZ	Aibibi	female
139	kk_KZ	Aibike	female
140	kk_KZ	Aibol	male
141	kk_KZ	Aibolat	male
142	kk_KZ	Aibyn	male
143	kk_KZ	Aida	female
144	kk_KZ	Aidai	female
145	kk_KZ	Aidan	male
146	kk_KZ	Aidana	female
147	kk_KZ	Aidaniya	female
148	kk_KZ	Aidar	male
149	kk_KZ	Aidara	female
150	kk_KZ	Aidaraly	male
151	kk_KZ	Aidarbek	male
152	kk_KZ	Aidargali	male
153	kk_KZ	Aidariya	female
154	kk_KZ	Aidarkhan	male
155	kk_KZ	Aidos	male
156	kk_KZ	Aidyn	male
157	kk_KZ	Aidynbek	male
158	kk_KZ	Aigabyl	male
159	kk_KZ	Aigaisha	female
160	kk_KZ	Aigali	male
161	kk_KZ	Aigansha	female
162	kk_KZ	Aiganym	female
163	kk_KZ	Aiganys	female
164	kk_KZ	Aigenzhe	female
165	kk_KZ	Aigerim	female
166	kk_KZ	Aigolkyn	female
167	kk_KZ	Aigul	female
168	kk_KZ	Aigyz	female
169	kk_KZ	Aiimbet	male
170	kk_KZ	Aikelbet	female
171	kk_KZ	Aiken	female
172	kk_KZ	Aikumis	female
173	kk_KZ	Aikun	female
174	kk_KZ	Aikyn	male
175	kk_KZ	Aimagambet	male
176	kk_KZ	Aimagan	male
177	kk_KZ	Aimak	male
178	kk_KZ	Aimanai	female
179	kk_KZ	Aimangul	female
180	kk_KZ	Aimankul	female
181	kk_KZ	Aimariya	female
182	kk_KZ	Aimash	female
183	kk_KZ	Aimat	male
184	kk_KZ	Aimauyt	male
185	kk_KZ	Aimira	female
186	kk_KZ	Aimish	male
187	kk_KZ	Aimukambet	male
188	kk_KZ	Aimurat	male
189	kk_KZ	Aimyrza	male
190	kk_KZ	Aina	female
191	kk_KZ	Ainabek	male
192	kk_KZ	Ainagul	female
193	kk_KZ	Ainakan	female
194	kk_KZ	Ainakul	female
195	kk_KZ	Ainash	female
196	kk_KZ	Ainasha	female
197	kk_KZ	Ainaziya	female
198	kk_KZ	Ainek	female
199	kk_KZ	Ainet	male
200	kk_KZ	Ainissa	female
201	kk_KZ	Ainur	female
202	kk_KZ	Ainura	female
203	kk_KZ	Ainuriya	female
204	kk_KZ	Aipar	male
205	kk_KZ	Aipara	female
206	kk_KZ	Airat	male
207	kk_KZ	Airyksha	female
208	kk_KZ	Aisa	male
209	kk_KZ	Aisara	female
210	kk_KZ	Aisary	male
211	kk_KZ	Aisaule	female
212	kk_KZ	Aisauyt	male
213	kk_KZ	Aisha	female
214	kk_KZ	Aishagul	female
215	kk_KZ	Aishaiym	female
216	kk_KZ	Aishakhan	female
217	kk_KZ	Aisholpan	female
218	kk_KZ	Aishuak	male
219	kk_KZ	Aishyk	male
220	kk_KZ	Aishym	female
221	kk_KZ	Aishynbai	male
222	kk_KZ	Aisipat	female
223	kk_KZ	Aisugir	male
224	kk_KZ	Aisulu	female
225	kk_KZ	Ait	male
226	kk_KZ	Aitak	male
227	kk_KZ	Aitakyn	male
228	kk_KZ	Aitali	male
229	kk_KZ	Aitan	male
230	kk_KZ	Aitaniya	female
231	kk_KZ	Aitas	male
232	kk_KZ	Aitaza	male
233	kk_KZ	Aitbai	male
234	kk_KZ	Aitbala	female
235	kk_KZ	Aitdana	female
236	kk_KZ	Aitek	male
237	kk_KZ	Aitemir	male
238	kk_KZ	Aiten	male
239	kk_KZ	Aitileu	male
240	kk_KZ	Aitkali	male
241	kk_KZ	Aitkozha	male
242	kk_KZ	Aitkozhan	male
243	kk_KZ	Aitkul	male
244	kk_KZ	Aitmagambet	male
245	kk_KZ	Aitmukambet	male
246	kk_KZ	Aitoldy	female
247	kk_KZ	Aitolys	female
248	kk_KZ	Aitu	male
249	kk_KZ	Aituar	male
250	kk_KZ	Aitugan	male
251	kk_KZ	Aityk	male
252	kk_KZ	Aitym	male
253	kk_KZ	Aitzhamal	female
254	kk_KZ	Aitzhan	male
255	kk_KZ	Aiym	female
256	kk_KZ	Aiymbet	male
257	kk_KZ	Aiymbibi	female
258	kk_KZ	Aiymbike	female
259	kk_KZ	Aiymgul	female
260	kk_KZ	Aiymsha	female
261	kk_KZ	Aiymzhan	female
262	kk_KZ	Aiza	female
263	kk_KZ	Aizada	female
264	kk_KZ	Aizar	male
265	kk_KZ	Aizara	female
266	kk_KZ	Aizeine	female
267	kk_KZ	Aizere	female
268	kk_KZ	Aizhaina	female
269	kk_KZ	Aizhaksym	female
270	kk_KZ	Aizhamal	female
271	kk_KZ	Aizhan	female
272	kk_KZ	Aizhanar	female
273	kk_KZ	Aizhaniya	female
274	kk_KZ	Aizharkyn	male
275	kk_KZ	Aizharyk	male
276	kk_KZ	Aizhas	male
277	kk_KZ	Aizhigit	male
278	kk_KZ	Aizhuldyz	female
279	kk_KZ	Aizhunis	female
280	kk_KZ	Aiziba	female
281	kk_KZ	Aiziya	female
282	kk_KZ	Akabai	male
283	kk_KZ	Akai	male
284	kk_KZ	Akaisha	female
285	kk_KZ	Akaltyn	female
286	kk_KZ	Akan	male
287	kk_KZ	Akaru	female
288	kk_KZ	Akbai	male
289	kk_KZ	Akbala	female
290	kk_KZ	Akbates	female
291	kk_KZ	Akbatima	female
292	kk_KZ	Akbau	male
293	kk_KZ	Akbayan	female
294	kk_KZ	Akberdi	male
295	kk_KZ	Akbergen	male
296	kk_KZ	Akbet	female
297	kk_KZ	Akbibi	female
298	kk_KZ	Akbike	female
299	kk_KZ	Akbilek	female
300	kk_KZ	Akboken	female
301	kk_KZ	Akbolat	male
302	kk_KZ	Akdilda	male
303	kk_KZ	Akedil	male
304	kk_KZ	Akerke	female
305	kk_KZ	Akgul	female
306	kk_KZ	Akhat	male
307	kk_KZ	Akhim	male
308	kk_KZ	Akhmedi	male
309	kk_KZ	Akhmet	male
310	kk_KZ	Akhmetali	male
311	kk_KZ	Akhmetbai	male
312	kk_KZ	Akhmetbek	male
313	kk_KZ	Akhmetiyar	male
314	kk_KZ	Akhmetkali	male
315	kk_KZ	Akhmetkhan	male
316	kk_KZ	Akhmetolla	male
317	kk_KZ	Akhmetsapa	male
318	kk_KZ	Akhmetshi	male
319	kk_KZ	Akhmetzhan	male
320	kk_KZ	Akhtamberdi	male
321	kk_KZ	Akim	male
322	kk_KZ	Akimbai	male
323	kk_KZ	Akimbek	male
324	kk_KZ	Akimgozha	male
325	kk_KZ	Akimkhan	male
326	kk_KZ	Akimzhan	male
327	kk_KZ	Akiram	male
328	kk_KZ	Akish	male
329	kk_KZ	Akizhan	male
330	kk_KZ	Akkagaz	female
331	kk_KZ	Akkatsha	female
332	kk_KZ	Akkenzhe	female
333	kk_KZ	Akkoshkar	male
334	kk_KZ	Akkozha	male
335	kk_KZ	Akkozy	male
336	kk_KZ	Akku	female
337	kk_KZ	Akkuba	female
338	kk_KZ	Akkumis	female
339	kk_KZ	Akkyz	female
340	kk_KZ	Aklima	female
341	kk_KZ	Akmagambet	male
342	kk_KZ	Akmambet	male
343	kk_KZ	Akmaral	female
344	kk_KZ	Akmarka	female
345	kk_KZ	Akmarzhan	female
346	kk_KZ	Akmukambet	male
347	kk_KZ	Aknazik	female
348	kk_KZ	Aknaziya	female
349	kk_KZ	Akniet	female
350	kk_KZ	Akniya	female
351	kk_KZ	Akpanbet	male
352	kk_KZ	Akpar	male
353	kk_KZ	Aksan	female
354	kk_KZ	Aksana	female
355	kk_KZ	Aksazan	female
356	kk_KZ	Akseleu	male
357	kk_KZ	Aksha	female
358	kk_KZ	Akshabak	female
359	kk_KZ	Aksholas	male
360	kk_KZ	Aksholpan	female
361	kk_KZ	Akshora	male
362	kk_KZ	Akshybyk	female
363	kk_KZ	Aksultan	male
364	kk_KZ	Aksulu	female
365	kk_KZ	Aksyiyk	male
366	kk_KZ	Aktai	male
367	kk_KZ	Aktailak	male
368	kk_KZ	Aktal	male
369	kk_KZ	Aktan	male
370	kk_KZ	Aktilek	male
371	kk_KZ	Aktokty	female
372	kk_KZ	Aktolkyn	female
373	kk_KZ	Aktolyk	female
374	kk_KZ	Aktolys	female
375	kk_KZ	Akushtap	female
376	kk_KZ	Akyk	female
377	kk_KZ	Akylbai	male
378	kk_KZ	Akylbek	male
379	kk_KZ	Akylima	female
380	kk_KZ	Akyn	male
381	kk_KZ	Akynali	male
382	kk_KZ	Akynzhan	male
383	kk_KZ	Akyrap	male
384	kk_KZ	Akysh	male
385	kk_KZ	Akzeinep	female
386	kk_KZ	Akzeinet	female
387	kk_KZ	Akzer	female
388	kk_KZ	Akzhamal	female
389	kk_KZ	Akzharkyn	male
390	kk_KZ	Akzhelek	female
391	kk_KZ	Akzhemis	female
392	kk_KZ	Akzhibek	female
393	kk_KZ	Akzhigit	male
394	kk_KZ	Akzhol	male
395	kk_KZ	Akzhunis	female
396	kk_KZ	Akzhupar	female
397	kk_KZ	Akzhurek	female
398	kk_KZ	Akziba	female
399	kk_KZ	Akzila	female
400	kk_KZ	Alai	male
401	kk_KZ	Alapa	female
402	kk_KZ	Alatau	male
403	kk_KZ	Alau	male
404	kk_KZ	Alban	male
405	kk_KZ	Albat	male
406	kk_KZ	Albatyr	male
407	kk_KZ	Albina	female
408	kk_KZ	Aldabergen	male
409	kk_KZ	Aldados	male
410	kk_KZ	Aldamurat	male
411	kk_KZ	Aldamzhar	male
412	kk_KZ	Aldan	male
413	kk_KZ	Aldar	male
414	kk_KZ	Aldash	male
415	kk_KZ	Alemgul	female
416	kk_KZ	Alemkul	female
417	kk_KZ	Alen	male
418	kk_KZ	Ales	male
419	kk_KZ	Alfiya	female
420	kk_KZ	Alga	male
421	kk_KZ	Algatai	male
422	kk_KZ	Algazy	male
423	kk_KZ	Algozha	male
424	kk_KZ	Algyr	male
425	kk_KZ	Ali	male
426	kk_KZ	Aliaidar	male
427	kk_KZ	Aliakpar	male
428	kk_KZ	Aliaskar	male
429	kk_KZ	Alibai	male
430	kk_KZ	Alibek	male
431	kk_KZ	Alibi	male
432	kk_KZ	Aliga	female
433	kk_KZ	Alikan	male
434	kk_KZ	Alila	female
435	kk_KZ	Alim	male
436	kk_KZ	Alima	female
437	kk_KZ	Alimbai	male
438	kk_KZ	Alimbek	male
439	kk_KZ	Alimbet	male
440	kk_KZ	Alimgazy	male
441	kk_KZ	Alimgozha	male
442	kk_KZ	Alimkhan	male
443	kk_KZ	Alimkul	male
444	kk_KZ	Alimzhan	male
445	kk_KZ	Alina	female
446	kk_KZ	Alipa	female
447	kk_KZ	Alipbai	male
448	kk_KZ	Alipbek	male
449	kk_KZ	Alish	male
450	kk_KZ	Alisha	female
451	kk_KZ	Alisher	male
452	kk_KZ	Alissa	female
453	kk_KZ	Aliya	female
454	kk_KZ	Aliza	female
455	kk_KZ	Alkadyr	male
456	kk_KZ	Alkagul	female
457	kk_KZ	Alkei	male
458	kk_KZ	Alken	male
459	kk_KZ	Alkhan	female
460	kk_KZ	Alkuat	male
461	kk_KZ	Alla	female
462	kk_KZ	Alma	female
463	kk_KZ	Almabai	male
464	kk_KZ	Almabek	male
465	kk_KZ	Almabike	female
466	kk_KZ	Almagul	female
467	kk_KZ	Almakan	male
468	kk_KZ	Almaniyaz	male
469	kk_KZ	Almas	male
470	kk_KZ	Almasbai	male
471	kk_KZ	Almasbek	male
472	kk_KZ	Almasha	female
473	kk_KZ	Almaskan	male
474	kk_KZ	Almaskul	female
475	kk_KZ	Almazhan	female
476	kk_KZ	Almaziya	female
477	kk_KZ	Almukambet	male
478	kk_KZ	Almurat	male
479	kk_KZ	Almurt	male
480	kk_KZ	Alnur	male
481	kk_KZ	Alpamys	male
482	kk_KZ	Alpan	male
483	kk_KZ	Alpar	male
484	kk_KZ	Alpys	male
485	kk_KZ	Alpysbai	male
486	kk_KZ	Alseiit	male
487	kk_KZ	Alsha	female
488	kk_KZ	Alshagyr	male
489	kk_KZ	Alshan	male
490	kk_KZ	Alshynbai	male
491	kk_KZ	Altai	male
492	kk_KZ	Altaibai	male
493	kk_KZ	Altaibek	male
494	kk_KZ	Altybai	male
495	kk_KZ	Altyn	female
496	kk_KZ	Altynai	female
497	kk_KZ	Altynbai	male
498	kk_KZ	Altynbek	male
499	kk_KZ	Altynbike	female
500	kk_KZ	Altyngul	female
501	kk_KZ	Altynsary	male
502	kk_KZ	Altynshash	female
503	kk_KZ	Altynzer	female
504	kk_KZ	Alua	female
505	kk_KZ	Aluaza	female
506	kk_KZ	Alybai	male
507	kk_KZ	Alzhan	male
508	kk_KZ	Alzhanbai	male
509	kk_KZ	Alzhapar	male
510	kk_KZ	Amanai	female
511	kk_KZ	Amanali	male
512	kk_KZ	Amanat	male
513	kk_KZ	Amanbai	male
514	kk_KZ	Amanbala	female
515	kk_KZ	Amanbek	male
516	kk_KZ	Amanbolat	male
517	kk_KZ	Amandos	male
518	kk_KZ	Amandyk	male
519	kk_KZ	Amangali	male
520	kk_KZ	Amangeldi	male
521	kk_KZ	Amangul	female
522	kk_KZ	Amaniya	female
523	kk_KZ	Amankesh	female
524	kk_KZ	Amankos	male
525	kk_KZ	Amansha	female
526	kk_KZ	Amanshy	male
527	kk_KZ	Amantai	male
528	kk_KZ	Amantur	male
529	kk_KZ	Amanzhan	male
530	kk_KZ	Amanzhol	male
531	kk_KZ	Ambe	male
532	kk_KZ	Amedi	male
533	kk_KZ	Amen	male
534	kk_KZ	Amila	female
535	kk_KZ	Amin	male
536	kk_KZ	Amina	female
537	kk_KZ	Amir	male
538	kk_KZ	Amira	female
539	kk_KZ	Amiraly	male
540	kk_KZ	Amirbai	male
541	kk_KZ	Amirbek	male
542	kk_KZ	Amire	male
543	kk_KZ	Amiren	male
544	kk_KZ	Amiresh	male
545	kk_KZ	Amirgali	male
546	kk_KZ	Amirgazy	male
547	kk_KZ	Amirkhan	male
548	kk_KZ	Amirlan	male
549	kk_KZ	Amirzhan	male
550	kk_KZ	Amreta	female
551	kk_KZ	Amze	male
552	kk_KZ	Anai	male
553	kk_KZ	Anapiya	female
554	kk_KZ	Anar	female
555	kk_KZ	Anara	female
556	kk_KZ	Anarbai	male
557	kk_KZ	Anarbek	male
558	kk_KZ	Anargul	female
559	kk_KZ	Anarkhan	female
560	kk_KZ	Anarzhan	female
561	kk_KZ	Anas	male
562	kk_KZ	Anasbek	male
563	kk_KZ	Anassiya	female
564	kk_KZ	Andamas	male
565	kk_KZ	Andas	male
566	kk_KZ	Anel	female
567	kk_KZ	Anes	male
568	kk_KZ	Anfissa	female
569	kk_KZ	Anipa	female
570	kk_KZ	Anissa	female
571	kk_KZ	Aniza	female
572	kk_KZ	Anna	female
573	kk_KZ	Ansagan	male
574	kk_KZ	Ansar	male
575	kk_KZ	Antai	male
576	kk_KZ	Anuar	male
577	kk_KZ	Anuarbek	male
578	kk_KZ	Anuarkhan	male
579	kk_KZ	Anuza	female
580	kk_KZ	Anzhela	female
581	kk_KZ	Apek	male
582	kk_KZ	Apes	male
583	kk_KZ	Apiza	female
584	kk_KZ	Appak	male
585	kk_KZ	Arabai	male
586	kk_KZ	Aragoniya	female
587	kk_KZ	Arai	male
588	kk_KZ	Araisha	female
589	kk_KZ	Aralbai	male
590	kk_KZ	Arbek	male
591	kk_KZ	Arbol	male
592	kk_KZ	Arda	female
593	kk_KZ	Ardan	male
594	kk_KZ	Ardat	male
595	kk_KZ	Areken	male
596	kk_KZ	Argyn	male
597	kk_KZ	Argynbai	male
598	kk_KZ	Arina	female
599	kk_KZ	Arip	male
600	kk_KZ	Aripa	female
601	kk_KZ	Aripbai	male
602	kk_KZ	Ariya	female
603	kk_KZ	Arkabai	male
604	kk_KZ	Arkalyk	male
605	kk_KZ	Arkat	male
606	kk_KZ	Arman	male
607	kk_KZ	Armat	male
608	kk_KZ	Arna	female
609	kk_KZ	Arnagul	female
610	kk_KZ	Arshagul	female
611	kk_KZ	Arshat	female
612	kk_KZ	Artyk	male
613	kk_KZ	Aru	female
614	kk_KZ	Aruash	male
615	kk_KZ	Arubike	female
616	kk_KZ	Arusha	female
617	kk_KZ	Aryk	male
618	kk_KZ	Arykbai	male
619	kk_KZ	Aryktai	male
620	kk_KZ	Aryn	male
621	kk_KZ	Aryndyk	male
622	kk_KZ	Aryngul	female
623	kk_KZ	Arys	male
624	kk_KZ	Arysbai	male
625	kk_KZ	Arystan	male
626	kk_KZ	Arystanbai	male
627	kk_KZ	Arystanbek	male
628	kk_KZ	Arystangali	male
629	kk_KZ	Arzada	female
630	kk_KZ	Arzeine	female
631	kk_KZ	Arziba	female
632	kk_KZ	Arziya	female
633	kk_KZ	Arzu	female
634	kk_KZ	Arzymbet	male
635	kk_KZ	Asfandiyar	male
636	kk_KZ	Ashai	male
637	kk_KZ	Ashambai	male
638	kk_KZ	Ashedan	male
639	kk_KZ	Ashekei	male
640	kk_KZ	Ashet	male
641	kk_KZ	Ashim	male
642	kk_KZ	Ashimbai	male
643	kk_KZ	Ashimkhan	male
644	kk_KZ	Ashir	male
645	kk_KZ	Ashirali	male
646	kk_KZ	Ashirbai	male
647	kk_KZ	Ashirbek	male
648	kk_KZ	Ashirgali	male
649	kk_KZ	Ashirkhan	male
650	kk_KZ	Ashirmurat	male
651	kk_KZ	Ashkei	male
652	kk_KZ	Ashken	male
653	kk_KZ	Askar	male
654	kk_KZ	Askarbai	male
655	kk_KZ	Askarbek	male
656	kk_KZ	Asken	male
657	kk_KZ	Asker	male
658	kk_KZ	Askhat	male
659	kk_KZ	Asli	female
660	kk_KZ	Aslima	female
661	kk_KZ	Asliya	female
662	kk_KZ	Aspara	female
663	kk_KZ	Aspaziya	female
664	kk_KZ	Aspet	male
665	kk_KZ	Assabai	male
666	kk_KZ	Assaiyn	male
667	kk_KZ	Assan	male
668	kk_KZ	Assanali	male
669	kk_KZ	Assanaly	male
670	kk_KZ	Assanbai	male
671	kk_KZ	Assanbek	male
672	kk_KZ	Assangali	male
673	kk_KZ	Assankhan	male
674	kk_KZ	Assel	female
675	kk_KZ	Assem	female
676	kk_KZ	Assembike	female
677	kk_KZ	Assemgul	female
678	kk_KZ	Assemkan	female
679	kk_KZ	Assemkhan	female
680	kk_KZ	Asset	male
681	kk_KZ	Assi	male
682	kk_KZ	Assima	female
683	kk_KZ	Assip	male
684	kk_KZ	Assipa	female
685	kk_KZ	Assiya	female
686	kk_KZ	Assykbai	male
687	kk_KZ	Assylai	female
688	kk_KZ	Assylbai	male
689	kk_KZ	Assylbek	male
690	kk_KZ	Assylbike	female
691	kk_KZ	Assylgozha	male
692	kk_KZ	Assylgul	female
693	kk_KZ	Assylima	female
694	kk_KZ	Assylkhan	male
695	kk_KZ	Assylmurat	male
696	kk_KZ	Assylsha	female
697	kk_KZ	Assyltan	female
698	kk_KZ	Assyltas	female
699	kk_KZ	Assylzada	female
700	kk_KZ	Astam	male
701	kk_KZ	Astassiya	female
702	kk_KZ	Atabai	male
703	kk_KZ	Atabek	male
704	kk_KZ	Atai	male
705	kk_KZ	Atakan	male
706	kk_KZ	Atalyk	male
707	kk_KZ	Atambek	male
708	kk_KZ	Atamkul	male
709	kk_KZ	Atamurat	male
710	kk_KZ	Atanbai	male
711	kk_KZ	Ataniyaz	male
712	kk_KZ	Atantai	male
713	kk_KZ	Atas	male
714	kk_KZ	Atei	male
715	kk_KZ	Atek	male
716	kk_KZ	Aten	male
717	kk_KZ	Atina	female
718	kk_KZ	Atir	female
719	kk_KZ	Atshabar	male
720	kk_KZ	Atygai	male
721	kk_KZ	Atym	male
722	kk_KZ	Atymtai	male
723	kk_KZ	Aubakir	male
724	kk_KZ	Auel	male
725	kk_KZ	Auelbai	male
726	kk_KZ	Auelbek	male
727	kk_KZ	Auesbai	male
728	kk_KZ	Aueskhan	male
729	kk_KZ	Auez	male
730	kk_KZ	Auezkhan	male
731	kk_KZ	Auganbai	male
732	kk_KZ	Aukebai	male
733	kk_KZ	Auken	male
734	kk_KZ	Aukhadi	male
735	kk_KZ	Auzha	female
736	kk_KZ	Ayan	male
737	kk_KZ	Ayanat	female
738	kk_KZ	Ayandyk	male
739	kk_KZ	Ayap	male
740	kk_KZ	Ayapbergen	male
741	kk_KZ	Ayaz	male
742	kk_KZ	Ayazbai	male
743	kk_KZ	Ayazbek	male
744	kk_KZ	Ayazhan	female
745	kk_KZ	Ayukhan	male
746	kk_KZ	Aza	female
747	kk_KZ	Azaliya	female
748	kk_KZ	Azamat	male
749	kk_KZ	Azamatsha	female
750	kk_KZ	Azat	male
751	kk_KZ	Azatgul	female
752	kk_KZ	Azatiya	female
753	kk_KZ	Azerbai	male
754	kk_KZ	Azerbaizhan	male
755	kk_KZ	Azhar	female
756	kk_KZ	Azharbek	male
757	kk_KZ	Azhargul	female
758	kk_KZ	Azharkhan	female
759	kk_KZ	Azhi	male
760	kk_KZ	Azhibai	male
761	kk_KZ	Azhibek	male
762	kk_KZ	Azhigali	male
763	kk_KZ	Azhimurat	male
764	kk_KZ	Azhkei	male
765	kk_KZ	Azi	male
766	kk_KZ	Aziga	female
767	kk_KZ	Azikha	female
768	kk_KZ	Azila	female
769	kk_KZ	Azilkan	male
770	kk_KZ	Azim	male
771	kk_KZ	Azima	female
772	kk_KZ	Azimat	female
773	kk_KZ	Azimbai	male
774	kk_KZ	Azimkhan	male
775	kk_KZ	Azimzhan	male
776	kk_KZ	Azina	female
777	kk_KZ	Azipa	female
778	kk_KZ	Aziya	female
779	kk_KZ	Aziyasha	female
780	kk_KZ	Aziz	male
781	kk_KZ	Aziza	female
782	kk_KZ	Azizkhan	male
783	kk_KZ	Azpza	female
784	kk_KZ	Babagali	male
785	kk_KZ	Babai	male
786	kk_KZ	Babak	male
787	kk_KZ	Babakhan	male
788	kk_KZ	Babalyk	male
789	kk_KZ	Babamurat	male
790	kk_KZ	Babanar	male
791	kk_KZ	Babaniyaz	male
792	kk_KZ	Babas	male
793	kk_KZ	Babassal	male
794	kk_KZ	Babatai	male
795	kk_KZ	Babazhan	male
796	kk_KZ	Babek	male
797	kk_KZ	Badam	male
798	kk_KZ	Badambai	male
799	kk_KZ	Badambek	male
800	kk_KZ	Badanai	female
801	kk_KZ	Baden	female
802	kk_KZ	Bader	female
803	kk_KZ	Badesh	female
804	kk_KZ	Badi	male
805	kk_KZ	Badiga	female
806	kk_KZ	Badigul	male
807	kk_KZ	Badigulzhamal	female
808	kk_KZ	Badinur	female
809	kk_KZ	Badirlen	male
810	kk_KZ	Badisha	female
811	kk_KZ	Badiya	female
812	kk_KZ	Badyr	male
813	kk_KZ	Bafa	male
814	kk_KZ	Bagai	male
815	kk_KZ	Bagashar	male
816	kk_KZ	Bagdar	male
817	kk_KZ	Bagila	female
818	kk_KZ	Baglan	male
819	kk_KZ	Bagybai	male
820	kk_KZ	Bagybek	male
821	kk_KZ	Bagymsha	female
822	kk_KZ	Bagyzbai	male
823	kk_KZ	Bai	male
824	kk_KZ	Baiakhmet	male
825	kk_KZ	Baiarystan	male
826	kk_KZ	Baibagys	male
827	kk_KZ	Baibak	male
828	kk_KZ	Baibakty	male
829	kk_KZ	Baibala	male
830	kk_KZ	Baibarys	male
831	kk_KZ	Baibatyr	male
832	kk_KZ	Baibek	male
833	kk_KZ	Baibol	male
834	kk_KZ	Baibolat	male
835	kk_KZ	Baiboldy	male
836	kk_KZ	Baibori	male
837	kk_KZ	Baibossyn	male
838	kk_KZ	Baibota	male
839	kk_KZ	Baiboz	male
840	kk_KZ	Baibura	male
841	kk_KZ	Baidabek	male
842	kk_KZ	Baidaly	male
843	kk_KZ	Baidar	male
844	kk_KZ	Baidash	male
845	kk_KZ	Baidaulet	male
846	kk_KZ	Baidilda	male
847	kk_KZ	Baidir	male
848	kk_KZ	Baidos	male
849	kk_KZ	Baigabyl	male
850	kk_KZ	Baigali	male
851	kk_KZ	Baiganat	male
852	kk_KZ	Baigani	male
853	kk_KZ	Baigara	male
854	kk_KZ	Baigatar	male
855	kk_KZ	Baigazy	male
856	kk_KZ	Baigeldi	male
857	kk_KZ	Baigenzhe	male
858	kk_KZ	Baigozha	male
859	kk_KZ	Baigut	male
860	kk_KZ	Baiish	male
861	kk_KZ	Baikazak	male
862	kk_KZ	Baiken	male
863	kk_KZ	Baikenes	male
864	kk_KZ	Baikonyr	male
865	kk_KZ	Baikoshkar	male
866	kk_KZ	Baikuat	male
867	kk_KZ	Baikut	male
868	kk_KZ	Baikutty	male
869	kk_KZ	Baily	male
870	kk_KZ	Baimadi	male
871	kk_KZ	Baimagambet	male
872	kk_KZ	Baimakan	male
873	kk_KZ	Baiman	male
874	kk_KZ	Baimanbek	male
875	kk_KZ	Baimat	male
876	kk_KZ	Baimatai	male
877	kk_KZ	Baimen	male
878	kk_KZ	Baimendi	male
879	kk_KZ	Baimolda	male
880	kk_KZ	Baimukambet	male
881	kk_KZ	Baimukan	male
882	kk_KZ	Baimurat	male
883	kk_KZ	Baimyrza	male
884	kk_KZ	Bainazar	male
885	kk_KZ	Bainur	male
886	kk_KZ	Baisal	male
887	kk_KZ	Baisalyk	male
888	kk_KZ	Baisan	male
889	kk_KZ	Baisar	male
890	kk_KZ	Baiseiit	male
891	kk_KZ	Baiserke	male
892	kk_KZ	Baisha	male
893	kk_KZ	Baishagyr	male
894	kk_KZ	Baishy	male
895	kk_KZ	Baishygan	male
896	kk_KZ	Baishynar	male
897	kk_KZ	Baitak	male
898	kk_KZ	Baitan	male
899	kk_KZ	Baitana	male
900	kk_KZ	Baitas	male
901	kk_KZ	Baiteli	male
902	kk_KZ	Baitemir	male
903	kk_KZ	Baiten	male
904	kk_KZ	Baiterek	male
905	kk_KZ	Baitik	male
906	kk_KZ	Baitogai	male
907	kk_KZ	Baitok	male
908	kk_KZ	Baitu	male
909	kk_KZ	Baitugan	male
910	kk_KZ	Baitur	male
911	kk_KZ	Baitursyn	male
912	kk_KZ	Baiuzak	male
913	kk_KZ	Baiymbet	male
914	kk_KZ	Baiynkol	male
915	kk_KZ	Baiyr	male
916	kk_KZ	Baiyrkas	male
917	kk_KZ	Baiys	male
918	kk_KZ	Baiyzbek	male
919	kk_KZ	Baizak	male
920	kk_KZ	Baizhan	male
921	kk_KZ	Baizharas	male
922	kk_KZ	Baizhigit	male
923	kk_KZ	Baizhol	male
924	kk_KZ	Baizhomart	male
925	kk_KZ	Bakai	male
926	kk_KZ	Bakau	male
927	kk_KZ	Bakbek	male
928	kk_KZ	Bakbergen	male
929	kk_KZ	Bakdaulet	male
930	kk_KZ	Bakei	male
931	kk_KZ	Baken	male
932	kk_KZ	Baki	male
933	kk_KZ	Bakibai	male
934	kk_KZ	Bakibala	female
935	kk_KZ	Bakir	male
936	kk_KZ	Bakisha	female
937	kk_KZ	Bakiya	female
938	kk_KZ	Bakizat	female
939	kk_KZ	Bakize	female
940	kk_KZ	Bakizhan	male
941	kk_KZ	Bakkozha	male
942	kk_KZ	Bakkuat	male
943	kk_KZ	Baksha	female
944	kk_KZ	Bakshagul	female
945	kk_KZ	Baktalap	male
946	kk_KZ	Baktarai	male
947	kk_KZ	Baktiyar	male
948	kk_KZ	Baktybai	male
949	kk_KZ	Baktygerei	male
950	kk_KZ	Baktygul	female
951	kk_KZ	Baktyzhar	male
952	kk_KZ	Bakyt	male
953	kk_KZ	Bakytzhamal	female
954	kk_KZ	Bakytzhan	male
955	kk_KZ	Balabai	male
956	kk_KZ	Balabek	male
957	kk_KZ	Balai	female
958	kk_KZ	Balaiym	female
959	kk_KZ	Balakai	male
960	kk_KZ	Balakaz	male
961	kk_KZ	Balakhmet	male
962	kk_KZ	Balamer	male
963	kk_KZ	Balamurat	male
964	kk_KZ	Balapan	male
965	kk_KZ	Balbala	female
966	kk_KZ	Balbek	male
967	kk_KZ	Balbike	female
968	kk_KZ	Balbyr	male
969	kk_KZ	Baldai	female
970	kk_KZ	Baldos	male
971	kk_KZ	Balerke	female
972	kk_KZ	Balgabai	male
973	kk_KZ	Balgabek	male
974	kk_KZ	Balgadisha	female
975	kk_KZ	Balgaisha	female
976	kk_KZ	Balganym	female
977	kk_KZ	Balgatsha	female
978	kk_KZ	Balgazy	male
979	kk_KZ	Balgozha	male
980	kk_KZ	Balgul	female
981	kk_KZ	Balgymbai	male
982	kk_KZ	Balgyn	female
983	kk_KZ	Balgynsha	female
984	kk_KZ	Balgyz	female
985	kk_KZ	Baliga	female
986	kk_KZ	Balisha	female
987	kk_KZ	Baliya	female
988	kk_KZ	Balkadisha	female
989	kk_KZ	Balkiya	female
990	kk_KZ	Balkuat	male
991	kk_KZ	Balkumis	female
992	kk_KZ	Balky	male
993	kk_KZ	Balkybai	male
994	kk_KZ	Balkybek	male
995	kk_KZ	Balmagambet	male
996	kk_KZ	Balman	male
997	kk_KZ	Balmukan	male
998	kk_KZ	Balmukhambet	male
999	kk_KZ	Balnur	female
1000	kk_KZ	Balsheker	female
1001	kk_KZ	Balta	male
1002	kk_KZ	Baltabai	male
1003	kk_KZ	Baltaban	male
1004	kk_KZ	Baltabek	male
1005	kk_KZ	Baltan	male
1006	kk_KZ	Baltash	male
1007	kk_KZ	Baltazar	male
1008	kk_KZ	Baluan	male
1009	kk_KZ	Baluangali	male
1010	kk_KZ	Balym	female
1011	kk_KZ	Balymsha	female
1012	kk_KZ	Balzada	female
1013	kk_KZ	Balzhan	female
1014	kk_KZ	Balziya	female
1015	kk_KZ	Banana	female
1016	kk_KZ	Banat	female
1017	kk_KZ	Banigat	male
1018	kk_KZ	Banu	female
1019	kk_KZ	Bapa	male
1020	kk_KZ	Bapai	male
1021	kk_KZ	Bapy	male
1022	kk_KZ	Barat	male
1023	kk_KZ	Bari	male
1024	kk_KZ	Barimbek	male
1025	kk_KZ	Barlybai	male
1026	kk_KZ	Barlyk	male
1027	kk_KZ	Barmak	male
1028	kk_KZ	Barmankul	male
1029	kk_KZ	Barsak	male
1030	kk_KZ	Barsha	female
1031	kk_KZ	Barshagul	female
1032	kk_KZ	Barshyn	female
1033	kk_KZ	Barshynai	female
1034	kk_KZ	Barys	male
1035	kk_KZ	Barysbek	male
1036	kk_KZ	Barzhaksy	male
1037	kk_KZ	Basbai	male
1038	kk_KZ	Bashan	male
1039	kk_KZ	Bashir	male
1040	kk_KZ	Baskan	male
1041	kk_KZ	Bassan	male
1042	kk_KZ	Bassar	male
1043	kk_KZ	Bassen	male
1044	kk_KZ	Bassibek	male
1045	kk_KZ	Bassym	male
1046	kk_KZ	Bastau	male
1047	kk_KZ	Bastaubai	male
1048	kk_KZ	Batai	male
1049	kk_KZ	Baten	female
1050	kk_KZ	Bates	female
1051	kk_KZ	Batika	female
1052	kk_KZ	Batima	female
1053	kk_KZ	Batiya	female
1054	kk_KZ	Batiza	female
1055	kk_KZ	Battal	male
1056	kk_KZ	Batyr	male
1057	kk_KZ	Batyraly	male
1058	kk_KZ	Batyrash	male
1059	kk_KZ	Batyrbai	male
1060	kk_KZ	Batyrbek	male
1061	kk_KZ	Batyrkan	male
1062	kk_KZ	Batyrkhan	male
1063	kk_KZ	Batyrlan	male
1064	kk_KZ	Batyrsha	male
1065	kk_KZ	Batyrulan	male
1066	kk_KZ	Batyrzhan	male
1067	kk_KZ	Baubek	male
1068	kk_KZ	Bauken	male
1069	kk_KZ	Bauyrzhan	male
1070	kk_KZ	Bayanbai	male
1071	kk_KZ	Bayandy	male
1072	kk_KZ	Bayansulu	female
1073	kk_KZ	Bayat	male
1074	kk_KZ	Bayazit	male
1075	kk_KZ	Bazai	male
1076	kk_KZ	Bazan	male
1077	kk_KZ	Bazar	male
1078	kk_KZ	Bazaraiym	female
1079	kk_KZ	Bazaraly	male
1080	kk_KZ	Bazarbai	male
1081	kk_KZ	Bazarbek	male
1082	kk_KZ	Bazargali	male
1083	kk_KZ	Bazargeldi	male
1084	kk_KZ	Bazargul	female
1085	kk_KZ	Bazen	male
1086	kk_KZ	Bazhen	male
1087	kk_KZ	Bazhtai	male
1088	kk_KZ	Bazigul	female
1089	kk_KZ	Bazila	female
1090	kk_KZ	Bazyl	male
1091	kk_KZ	Bazym	male
1092	kk_KZ	Bedelbai	male
1093	kk_KZ	Bedelbek	male
1094	kk_KZ	Bedelkan	male
1095	kk_KZ	Bedelzhan	male
1096	kk_KZ	Beden	male
1097	kk_KZ	Begaidar	male
1098	kk_KZ	Begaiym	female
1099	kk_KZ	Begaly	male
1100	kk_KZ	Begdilda	male
1101	kk_KZ	Begei	male
1102	kk_KZ	Begen	male
1103	kk_KZ	Begendik	male
1104	kk_KZ	Begesh	male
1105	kk_KZ	Begim	male
1106	kk_KZ	Begimbai	male
1107	kk_KZ	Begimbet	male
1108	kk_KZ	Begimsal	male
1109	kk_KZ	Begish	male
1110	kk_KZ	Beibit	male
1111	kk_KZ	Beibitgul	female
1112	kk_KZ	Beibitzhan	male
1113	kk_KZ	Beiil	male
1114	kk_KZ	Beiimbet	male
1115	kk_KZ	Beiis	male
1116	kk_KZ	Beiissali	male
1117	kk_KZ	Beikhan	male
1118	kk_KZ	Beikut	male
1119	kk_KZ	Beinesh	female
1120	kk_KZ	Beisebai	male
1121	kk_KZ	Beisebek	male
1122	kk_KZ	Beisek	male
1123	kk_KZ	Beisekei	male
1124	kk_KZ	Beisen	male
1125	kk_KZ	Beisenali	male
1126	kk_KZ	Beisenbai	male
1127	kk_KZ	Beisenbi	male
1128	kk_KZ	Beisengali	male
1129	kk_KZ	Beiseu	male
1130	kk_KZ	Bekaidar	male
1131	kk_KZ	Bekbai	male
1132	kk_KZ	Bekbatyr	male
1133	kk_KZ	Bekbau	male
1134	kk_KZ	Bekberdi	male
1135	kk_KZ	Bekbergen	male
1136	kk_KZ	Bekbol	male
1137	kk_KZ	Bekbolat	male
1138	kk_KZ	Bekbossyn	male
1139	kk_KZ	Bekdaiyr	male
1140	kk_KZ	Bekdana	female
1141	kk_KZ	Bekebai	male
1142	kk_KZ	Bekembai	male
1143	kk_KZ	Beken	male
1144	kk_KZ	Bekesh	male
1145	kk_KZ	Beket	male
1146	kk_KZ	Beketai	male
1147	kk_KZ	Bekezhan	male
1148	kk_KZ	Bekin	male
1149	kk_KZ	Bekish	male
1150	kk_KZ	Bekkali	male
1151	kk_KZ	Bekkeldi	male
1152	kk_KZ	Bekkozha	male
1153	kk_KZ	Beklan	male
1154	kk_KZ	Bekmagambet	male
1155	kk_KZ	Bekman	male
1156	kk_KZ	Bekmukhambet	male
1157	kk_KZ	Bekmurat	male
1158	kk_KZ	Beknar	male
1159	kk_KZ	Beknaz	female
1160	kk_KZ	Beknazar	male
1161	kk_KZ	Bekniyaz	male
1162	kk_KZ	Bekpar	male
1163	kk_KZ	Bekpembet	male
1164	kk_KZ	Beksana	female
1165	kk_KZ	Bekseiit	male
1166	kk_KZ	Beksultan	male
1167	kk_KZ	Beksulu	female
1168	kk_KZ	Bektai	male
1169	kk_KZ	Bektas	male
1170	kk_KZ	Bektau	male
1171	kk_KZ	Bektemir	male
1172	kk_KZ	Bektemis	male
1173	kk_KZ	Bekten	male
1174	kk_KZ	Bektibai	male
1175	kk_KZ	Bektileu	male
1176	kk_KZ	Bektur	male
1177	kk_KZ	Bekturgan	male
1178	kk_KZ	Bektursyn	male
1179	kk_KZ	Bekzada	female
1180	kk_KZ	Bekzhan	male
1181	kk_KZ	Bekzhassar	male
1182	kk_KZ	Bekzhigit	male
1183	kk_KZ	Bekziya	female
1184	kk_KZ	Belassar	male
1185	kk_KZ	Belassyl	male
1186	kk_KZ	Belbai	male
1187	kk_KZ	Belberdi	male
1188	kk_KZ	Belbota	male
1189	kk_KZ	Belekei	male
1190	kk_KZ	Beles	male
1191	kk_KZ	Belgemer	male
1192	kk_KZ	Belgibai	male
1193	kk_KZ	Belibai	male
1194	kk_KZ	Bella	female
1195	kk_KZ	Berdali	male
1196	kk_KZ	Berden	male
1197	kk_KZ	Berdi	male
1198	kk_KZ	Berdibai	male
1199	kk_KZ	Berdiken	male
1200	kk_KZ	Berdimurat	male
1201	kk_KZ	Berdiyar	male
1202	kk_KZ	Bereket	male
1203	kk_KZ	Beren	male
1204	kk_KZ	Bergali	male
1205	kk_KZ	Bergen	male
1206	kk_KZ	Berik	male
1207	kk_KZ	Berikbai	male
1208	kk_KZ	Beril	male
1209	kk_KZ	Berish	male
1210	kk_KZ	Beristen	male
1211	kk_KZ	Berkaiyr	male
1212	kk_KZ	Berkei	male
1213	kk_KZ	Berkin	male
1214	kk_KZ	Berkinbai	male
1215	kk_KZ	Bernar	male
1216	kk_KZ	Berniyaz	male
1217	kk_KZ	Berta	female
1218	kk_KZ	Berzhan	male
1219	kk_KZ	Besbai	male
1220	kk_KZ	Betila	female
1221	kk_KZ	Biakhmet	male
1222	kk_KZ	Biali	male
1223	kk_KZ	Bibagul	female
1224	kk_KZ	Bibaisha	female
1225	kk_KZ	Bibatyr	male
1226	kk_KZ	Bibi	female
1227	kk_KZ	Bibigaisha	female
1228	kk_KZ	Bibigul	female
1229	kk_KZ	Bibikamila	female
1230	kk_KZ	Bibikan	female
1231	kk_KZ	Bibikhanym	female
1232	kk_KZ	Bibinur	female
1233	kk_KZ	Bibish	female
1234	kk_KZ	Bibissara	female
1235	kk_KZ	Bibizada	female
1236	kk_KZ	Bibizhamal	female
1237	kk_KZ	Bibizhan	female
1238	kk_KZ	Bidaibek	male
1239	kk_KZ	Bigaisha	female
1240	kk_KZ	Bigalym	male
1241	kk_KZ	Biganym	female
1242	kk_KZ	Bigaripa	female
1243	kk_KZ	Bigeldi	male
1244	kk_KZ	Bike	female
1245	kk_KZ	Bikenai	female
1246	kk_KZ	Bilal	male
1247	kk_KZ	Bilgir	male
1248	kk_KZ	Bilim	male
1249	kk_KZ	Bilimkan	female
1250	kk_KZ	Bilisbai	male
1251	kk_KZ	Bilzhan	male
1252	kk_KZ	Bimagambet	male
1253	kk_KZ	Bimakan	male
1254	kk_KZ	Biman	male
1255	kk_KZ	Bimet	male
1256	kk_KZ	Birimzhan	male
1257	kk_KZ	Birken	male
1258	kk_KZ	Birman	male
1259	kk_KZ	Birzhan	male
1260	kk_KZ	Bissali	male
1261	kk_KZ	Bissen	male
1262	kk_KZ	Bitai	male
1263	kk_KZ	Bitan	male
1264	kk_KZ	Bitim	male
1265	kk_KZ	Biyash	male
1266	kk_KZ	Bizak	male
1267	kk_KZ	Bizat	male
1268	kk_KZ	Bizaure	female
1269	kk_KZ	Bizhamal	female
1270	kk_KZ	Bizhan	male
1271	kk_KZ	Bizhaniya	female
1272	kk_KZ	Bobei	male
1273	kk_KZ	Bobet	male
1274	kk_KZ	Bodan	male
1275	kk_KZ	Bodaubai	male
1276	kk_KZ	Boden	male
1277	kk_KZ	Bodesh	male
1278	kk_KZ	Bodyk	male
1279	kk_KZ	Bokei	male
1280	kk_KZ	Boken	female
1281	kk_KZ	Bokenbai	male
1282	kk_KZ	Bolat	male
1283	kk_KZ	Bolatbek	male
1284	kk_KZ	Bolatkhan	male
1285	kk_KZ	Bolatkozha	male
1286	kk_KZ	Bolatzhan	male
1287	kk_KZ	Bole	male
1288	kk_KZ	Bolebai	male
1289	kk_KZ	Bolgan	male
1290	kk_KZ	Bolganbai	male
1291	kk_KZ	Bolken	male
1292	kk_KZ	Bolsynai	female
1293	kk_KZ	Bolsynbek	male
1294	kk_KZ	Boltirik	male
1295	kk_KZ	Bopa	female
1296	kk_KZ	Bopazhan	female
1297	kk_KZ	Boran	male
1298	kk_KZ	Boranbai	male
1299	kk_KZ	Borangazy	male
1300	kk_KZ	Boranshy	male
1301	kk_KZ	Borash	male
1302	kk_KZ	Borgazy	male
1303	kk_KZ	Bori	male
1304	kk_KZ	Boribai	male
1305	kk_KZ	Bortai	male
1306	kk_KZ	Boshai	male
1307	kk_KZ	Boshan	male
1308	kk_KZ	Boshtai	male
1309	kk_KZ	Bota	female
1310	kk_KZ	Botabai	male
1311	kk_KZ	Botagoz	female
1312	kk_KZ	Botai	male
1313	kk_KZ	Botakoz	female
1314	kk_KZ	Botan	male
1315	kk_KZ	Botanbek	male
1316	kk_KZ	Botash	male
1317	kk_KZ	Botazhan	female
1318	kk_KZ	Botbai	male
1319	kk_KZ	Bozai	male
1320	kk_KZ	Bozbai	male
1321	kk_KZ	Bozdak	male
1322	kk_KZ	Bozhei	male
1323	kk_KZ	Boztai	male
1324	kk_KZ	Bozymbai	male
1325	kk_KZ	Bozymbek	male
1326	kk_KZ	Bozzhan	male
1327	kk_KZ	Bozzhigit	male
1328	kk_KZ	Bubaisha	female
1329	kk_KZ	Bubi	female
1330	kk_KZ	Bubikhan	female
1331	kk_KZ	Bubish	female
1332	kk_KZ	Bubisha	female
1333	kk_KZ	Bubishaiym	female
1334	kk_KZ	Bugybai	male
1335	kk_KZ	Bukas	male
1336	kk_KZ	Buke	male
1337	kk_KZ	Bukhar	male
1338	kk_KZ	Bukharbai	male
1339	kk_KZ	Bulabai	male
1340	kk_KZ	Bulakbai	male
1341	kk_KZ	Bulanbai	male
1342	kk_KZ	Bulbul	female
1343	kk_KZ	Bulde	female
1344	kk_KZ	Buldirshin	female
1345	kk_KZ	Buldybai	male
1346	kk_KZ	Bulkysh	male
1347	kk_KZ	Bulzhan	female
1348	kk_KZ	Burabai	male
1349	kk_KZ	Burakan	male
1350	kk_KZ	Burash	male
1351	kk_KZ	Burkhan	male
1352	kk_KZ	Burkhat	male
1353	kk_KZ	Burkit	male
1354	kk_KZ	Burkitbai	male
1355	kk_KZ	Burlibai	male
1356	kk_KZ	Dabyl	male
1357	kk_KZ	Dabyr	male
1358	kk_KZ	Dabys	male
1359	kk_KZ	Dadabai	male
1360	kk_KZ	Dadai	male
1361	kk_KZ	Dagiya	female
1362	kk_KZ	Daiana	female
1363	kk_KZ	Daima	female
1364	kk_KZ	Daira	female
1365	kk_KZ	Dairabai	male
1366	kk_KZ	Dairash	male
1367	kk_KZ	Daiyn	male
1368	kk_KZ	Daiyr	male
1369	kk_KZ	Daiyrbek	male
1370	kk_KZ	Daiyrzhan	male
1371	kk_KZ	Dalbek	male
1372	kk_KZ	Dalelkhan	male
1373	kk_KZ	Dalen	male
1374	kk_KZ	Dalila	female
1375	kk_KZ	Damai	male
1376	kk_KZ	Dambek	male
1377	kk_KZ	Damegul	female
1378	kk_KZ	Damek	male
1379	kk_KZ	Dameli	female
1380	kk_KZ	Damesh	female
1381	kk_KZ	Dametai	female
1382	kk_KZ	Damezhan	female
1383	kk_KZ	Damiga	female
1384	kk_KZ	Damina	female
1385	kk_KZ	Damir	male
1386	kk_KZ	Damira	female
1387	kk_KZ	Damisha	female
1388	kk_KZ	Damyl	male
1389	kk_KZ	Dana	female
1390	kk_KZ	Danagul	female
1391	kk_KZ	Danai	male
1392	kk_KZ	Danaibek	male
1393	kk_KZ	Danalyk	male
1394	kk_KZ	Danara	female
1395	kk_KZ	Danaziya	female
1396	kk_KZ	Dandai	male
1397	kk_KZ	Danegul	female
1398	kk_KZ	Daneker	female
1399	kk_KZ	Danen	male
1400	kk_KZ	Danesh	female
1401	kk_KZ	Danissa	female
1402	kk_KZ	Daniya	female
1403	kk_KZ	Daniyal	male
1404	kk_KZ	Daniyar	male
1405	kk_KZ	Danyshpan	male
1406	kk_KZ	Daragul	female
1407	kk_KZ	Daras	male
1408	kk_KZ	Daren	male
1409	kk_KZ	Dariga	female
1410	kk_KZ	Darigul	female
1411	kk_KZ	Dariko	female
1412	kk_KZ	Darish	male
1413	kk_KZ	Dariya	female
1414	kk_KZ	Darizhan	female
1415	kk_KZ	Darkei	male
1416	kk_KZ	Darkenbai	male
1417	kk_KZ	Darkhan	male
1418	kk_KZ	Darkhanbai	male
1419	kk_KZ	Darmen	male
1420	kk_KZ	Darula	female
1421	kk_KZ	Daryn	male
1422	kk_KZ	Darzhan	male
1423	kk_KZ	Darzhuman	male
1424	kk_KZ	Dastan	male
1425	kk_KZ	Dastanbek	male
1426	kk_KZ	Daua	female
1427	kk_KZ	Daubek	male
1428	kk_KZ	Dauen	male
1429	kk_KZ	Dauir	male
1430	kk_KZ	Dauirbek	male
1431	kk_KZ	Dauit	male
1432	kk_KZ	Dauitali	male
1433	kk_KZ	Daukebai	male
1434	kk_KZ	Daulen	male
1435	kk_KZ	Daulenkhan	male
1436	kk_KZ	Daulet	male
1437	kk_KZ	Dauletali	male
1438	kk_KZ	Dauletbai	male
1439	kk_KZ	Dauletbak	male
1440	kk_KZ	Dauletbek	male
1441	kk_KZ	Dauletgali	male
1442	kk_KZ	Dauletgazy	male
1443	kk_KZ	Dauletiyar	male
1444	kk_KZ	Dauletkali	male
1445	kk_KZ	Dauletkeldi	male
1446	kk_KZ	Dauletkerei	male
1447	kk_KZ	Dauletkhan	male
1448	kk_KZ	Dauletshe	male
1449	kk_KZ	Dauren	male
1450	kk_KZ	Daurenbek	male
1451	kk_KZ	Dautai	male
1452	kk_KZ	Dauylbai	male
1453	kk_KZ	Degdar	male
1454	kk_KZ	Demei	male
1455	kk_KZ	Demesh	male
1456	kk_KZ	Demessin	male
1457	kk_KZ	Demetan	male
1458	kk_KZ	Demeu	male
1459	kk_KZ	Demiyat	male
1460	kk_KZ	Dendar	male
1461	kk_KZ	Denesh	male
1462	kk_KZ	Denis	male
1463	kk_KZ	Derbai	male
1464	kk_KZ	Derbissali	male
1465	kk_KZ	Derlik	male
1466	kk_KZ	Diana	female
1467	kk_KZ	Dias	male
1468	kk_KZ	Dibai	male
1469	kk_KZ	Didara	female
1470	kk_KZ	Didarbek	male
1471	kk_KZ	Diiara	female
1472	kk_KZ	Dikan	male
1473	kk_KZ	Dikanbai	male
1474	kk_KZ	Dila	female
1475	kk_KZ	Dilara	female
1476	kk_KZ	Dilbar	female
1477	kk_KZ	Dilbara	female
1478	kk_KZ	Dilda	female
1479	kk_KZ	Dildabek	male
1480	kk_KZ	Dildash	female
1481	kk_KZ	Dilnaz	female
1482	kk_KZ	Dina	female
1483	kk_KZ	Dinara	female
1484	kk_KZ	Dinassyl	male
1485	kk_KZ	Dinmukhambet	male
1486	kk_KZ	Diyar	male
1487	kk_KZ	Diyara	female
1488	kk_KZ	Diyarbek	male
1489	kk_KZ	Dodan	male
1490	kk_KZ	Doiman	male
1491	kk_KZ	Dolai	male
1492	kk_KZ	Dolan	male
1493	kk_KZ	Dollores	female
1494	kk_KZ	Donai	male
1495	kk_KZ	Donbai	male
1496	kk_KZ	Donbek	male
1497	kk_KZ	Donentai	male
1498	kk_KZ	Donkei	male
1499	kk_KZ	Dos	male
1500	kk_KZ	Dosbai	male
1501	kk_KZ	Dosbergen	male
1502	kk_KZ	Doskara	male
1503	kk_KZ	Doskei	male
1504	kk_KZ	Doskeldi	male
1505	kk_KZ	Dosmet	male
1506	kk_KZ	Dosmukambet	male
1507	kk_KZ	Dosmukan	male
1508	kk_KZ	Dospan	male
1509	kk_KZ	Dossai	male
1510	kk_KZ	Dossaibek	male
1511	kk_KZ	Dossak	male
1512	kk_KZ	Dossali	male
1513	kk_KZ	Dossan	male
1514	kk_KZ	Dossym	male
1515	kk_KZ	Dossymbek	male
1516	kk_KZ	Dossymzhan	male
1517	kk_KZ	Dostak	male
1518	kk_KZ	Dostan	male
1519	kk_KZ	Dostiyar	male
1520	kk_KZ	Doszhan	male
1521	kk_KZ	Dotan	male
1522	kk_KZ	Duan	female
1523	kk_KZ	Duanbai	male
1524	kk_KZ	Dubai	male
1525	kk_KZ	Dudar	male
1526	kk_KZ	Duisebai	male
1527	kk_KZ	Duisek	male
1528	kk_KZ	Duisekei	male
1529	kk_KZ	Duisen	male
1530	kk_KZ	Duisenbai	male
1531	kk_KZ	Duisenbi	male
1532	kk_KZ	Duisetai	male
1533	kk_KZ	Dukenbai	male
1534	kk_KZ	Dulat	male
1535	kk_KZ	Dulatkhan	male
1536	kk_KZ	Duman	male
1537	kk_KZ	Dumangul	female
1538	kk_KZ	Dungenbai	male
1539	kk_KZ	Duniezada	female
1540	kk_KZ	Duniya	female
1541	kk_KZ	Durbai	male
1542	kk_KZ	Durbek	male
1543	kk_KZ	Durdana	female
1544	kk_KZ	Duriya	female
1545	kk_KZ	Dutbai	male
1546	kk_KZ	Dybys	female
1547	kk_KZ	Eduart	male
1548	kk_KZ	Elbrus	male
1549	kk_KZ	Eleonora	female
1550	kk_KZ	Ella	female
1551	kk_KZ	Elvira	female
1552	kk_KZ	Emil	male
1553	kk_KZ	Emma	female
1554	kk_KZ	Era	female
1555	kk_KZ	Ernest	male
1556	kk_KZ	Faiyz	male
1557	kk_KZ	Faizi	male
1558	kk_KZ	Faizolla	male
1559	kk_KZ	Faizrakhman	male
1560	kk_KZ	Fakhir	male
1561	kk_KZ	Fakhyr	male
1562	kk_KZ	Farid	male
1563	kk_KZ	Farida	female
1564	kk_KZ	Fariza	female
1565	kk_KZ	Farkhat	male
1566	kk_KZ	Faruza	female
1567	kk_KZ	Fatikh	male
1568	kk_KZ	Fatima	female
1569	kk_KZ	Fatkholla	male
1570	kk_KZ	Fauziya	female
1571	kk_KZ	Fazila	female
1572	kk_KZ	Faziya	female
1573	kk_KZ	Fazyl	male
1574	kk_KZ	Feliks	male
1575	kk_KZ	Firoza	female
1576	kk_KZ	Firuza	female
1577	kk_KZ	Flora	female
1578	kk_KZ	Furkat	male
1579	kk_KZ	Gabbas	male
1580	kk_KZ	Gabdiman	male
1581	kk_KZ	Gabdolla	male
1582	kk_KZ	Gabdyr	male
1583	kk_KZ	Gabiden	male
1584	kk_KZ	Gabidolla	male
1585	kk_KZ	Gabit	male
1586	kk_KZ	Gabitkhan	male
1587	kk_KZ	Gabsattar	male
1588	kk_KZ	Gafar	male
1589	kk_KZ	Gafu	male
1590	kk_KZ	Gafura	female
1591	kk_KZ	Gaini	female
1592	kk_KZ	Gainigul	female
1593	kk_KZ	Gainikamal	female
1594	kk_KZ	Gainizhamal	female
1595	kk_KZ	Gaisa	male
1596	kk_KZ	Gaisha	female
1597	kk_KZ	Gali	male
1598	kk_KZ	Galiakpar	male
1599	kk_KZ	Galiaskar	male
1600	kk_KZ	Galila	female
1601	kk_KZ	Galima	female
1602	kk_KZ	Galina	female
1603	kk_KZ	Galiya	female
1604	kk_KZ	Galym	male
1605	kk_KZ	Galymbai	male
1606	kk_KZ	Galymbek	male
1607	kk_KZ	Galymzhan	male
1608	kk_KZ	Gandira	female
1609	kk_KZ	Gani	male
1610	kk_KZ	Ganibek	male
1611	kk_KZ	Ganna	female
1612	kk_KZ	Gappar	male
1613	kk_KZ	Gappas	male
1614	kk_KZ	Garifa	female
1615	kk_KZ	Garifolla	male
1616	kk_KZ	Gatau	male
1617	kk_KZ	Gaukhar	female
1618	kk_KZ	Gaukhariya	female
1619	kk_KZ	Gayana	female
1620	kk_KZ	Gazima	female
1621	kk_KZ	Gaziya	female
1622	kk_KZ	Gaziz	male
1623	kk_KZ	Gaziza	female
1624	kk_KZ	Gazizbek	male
1625	kk_KZ	Gazizzhamal	female
1626	kk_KZ	Gibatolla	male
1627	kk_KZ	Gidayat	male
1628	kk_KZ	Ginayat	male
1629	kk_KZ	Gizat	male
1630	kk_KZ	Gubaidolla	male
1631	kk_KZ	Gulai	female
1632	kk_KZ	Gulaiim	female
1633	kk_KZ	Gulaina	female
1634	kk_KZ	Gulaisha	female
1635	kk_KZ	Gulaiym	female
1636	kk_KZ	Gulam	male
1637	kk_KZ	Gulara	female
1638	kk_KZ	Gulat	female
1639	kk_KZ	Gulazhar	female
1640	kk_KZ	Gulbadan	female
1641	kk_KZ	Gulbakhram	female
1642	kk_KZ	Gulbaksha	female
1643	kk_KZ	Gulbanat	female
1644	kk_KZ	Gulbanu	female
1645	kk_KZ	Gulbara	female
1646	kk_KZ	Gulbarash	female
1647	kk_KZ	Gulbarsha	female
1648	kk_KZ	Gulbarshyn	female
1649	kk_KZ	Gulbayan	female
1650	kk_KZ	Gulbazira	female
1651	kk_KZ	Gulbibi	female
1652	kk_KZ	Gulbolsyn	female
1653	kk_KZ	Guldana	female
1654	kk_KZ	Guldara	female
1655	kk_KZ	Guldariya	female
1656	kk_KZ	Guldarkhan	female
1657	kk_KZ	Guleikan	female
1658	kk_KZ	Gulfaraz	female
1659	kk_KZ	Gulgaisha	female
1660	kk_KZ	Gulissa	female
1661	kk_KZ	Gulkhanym	female
1662	kk_KZ	Gulmara	female
1663	kk_KZ	Gulmariya	female
1664	kk_KZ	Gulmarzhan	female
1665	kk_KZ	Gulmerei	female
1666	kk_KZ	Gulmira	female
1667	kk_KZ	Gulnafissa	female
1668	kk_KZ	Gulnakissa	female
1669	kk_KZ	Gulnar	female
1670	kk_KZ	Gulnara	female
1671	kk_KZ	Gulnaz	female
1672	kk_KZ	Gulnazat	female
1673	kk_KZ	Gulnazira	female
1674	kk_KZ	Gulnissa	female
1675	kk_KZ	Gulnur	female
1676	kk_KZ	Gulnura	female
1677	kk_KZ	Gulpan	female
1678	kk_KZ	Gulpara	female
1679	kk_KZ	Gulpash	female
1680	kk_KZ	Gulrauza	female
1681	kk_KZ	Gulsagyra	female
1682	kk_KZ	Gulsanat	female
1683	kk_KZ	Gulsara	female
1684	kk_KZ	Gulshar	female
1685	kk_KZ	Gulshara	female
1686	kk_KZ	Gulsharuan	female
1687	kk_KZ	Gulshash	female
1688	kk_KZ	Gulshat	female
1689	kk_KZ	Gulsheker	female
1690	kk_KZ	Gulsim	female
1691	kk_KZ	Gulsinai	female
1692	kk_KZ	Gulsipat	female
1693	kk_KZ	Gulstan	female
1694	kk_KZ	Gulzada	female
1695	kk_KZ	Gulzagida	female
1696	kk_KZ	Gulzagila	female
1697	kk_KZ	Gulzagira	female
1698	kk_KZ	Gulzai	female
1699	kk_KZ	Gulzara	female
1700	kk_KZ	Gulzarifa	female
1701	kk_KZ	Gulzariya	female
1702	kk_KZ	Gulzeinep	female
1703	kk_KZ	Gulzhaina	female
1704	kk_KZ	Gulzhamal	female
1705	kk_KZ	Gulzhamila	female
1706	kk_KZ	Gulzhan	female
1707	kk_KZ	Gulzhanar	female
1708	kk_KZ	Gulzhau	female
1709	kk_KZ	Gulzhaukhar	female
1710	kk_KZ	Gulzhazira	female
1711	kk_KZ	Gulzhenis	female
1712	kk_KZ	Gulzhikhan	female
1713	kk_KZ	Gulzhiya	female
1714	kk_KZ	Gulzhiyan	female
1715	kk_KZ	Gulzhu	female
1716	kk_KZ	Gulzina	female
1717	kk_KZ	Gulzipa	female
1718	kk_KZ	Gulzira	female
1719	kk_KZ	Gumar	male
1720	kk_KZ	Gusman	male
1721	kk_KZ	Gusmangali	male
1722	kk_KZ	Gylman	male
1723	kk_KZ	Iba	female
1724	kk_KZ	Ibagul	female
1725	kk_KZ	Ibaly	female
1726	kk_KZ	Ibat	male
1727	kk_KZ	Ibatai	male
1728	kk_KZ	Ibatzhan	male
1729	kk_KZ	Ibazar	male
1730	kk_KZ	Ibazhan	female
1731	kk_KZ	Ibiken	male
1732	kk_KZ	Ibish	male
1733	kk_KZ	Ibitan	male
1734	kk_KZ	Ibizhan	male
1735	kk_KZ	Ibni	male
1736	kk_KZ	Ibragim	male
1737	kk_KZ	Ideyat	male
1738	kk_KZ	Iembai	male
1739	kk_KZ	Igen	male
1740	kk_KZ	Igenbai	male
1741	kk_KZ	Igidaulet	male
1742	kk_KZ	Igilik	male
1743	kk_KZ	Igissin	male
1744	kk_KZ	Ikrama	female
1745	kk_KZ	Ikrash	male
1746	kk_KZ	Ilash	female
1747	kk_KZ	Ilebai	male
1748	kk_KZ	Iles	female
1749	kk_KZ	Ilimkan	female
1750	kk_KZ	Iliyas	male
1751	kk_KZ	Ilmar	male
1752	kk_KZ	Imak	male
1753	kk_KZ	Imanali	male
1754	kk_KZ	Imanas	male
1755	kk_KZ	Imanbai	male
1756	kk_KZ	Imanbek	male
1757	kk_KZ	Imangali	male
1758	kk_KZ	Imangazy	male
1759	kk_KZ	Imankul	male
1760	kk_KZ	Imantai	male
1761	kk_KZ	Imanzhussip	male
1762	kk_KZ	Imara	female
1763	kk_KZ	Imash	male
1764	kk_KZ	Imat	male
1765	kk_KZ	Imer	male
1766	kk_KZ	Inayat	male
1767	kk_KZ	Indira	female
1768	kk_KZ	Inessa	female
1769	kk_KZ	Inga	female
1770	kk_KZ	Inkarbek	male
1771	kk_KZ	Inzhu	female
1772	kk_KZ	Ira	female
1773	kk_KZ	Irada	female
1774	kk_KZ	Iraida	female
1775	kk_KZ	Irina	female
1776	kk_KZ	Irma	female
1777	kk_KZ	Isa	male
1778	kk_KZ	Isabai	male
1779	kk_KZ	Isabek	male
1780	kk_KZ	Isadil	male
1781	kk_KZ	Isagali	male
1782	kk_KZ	Isak	male
1783	kk_KZ	Isakai	male
1784	kk_KZ	Isakan	male
1785	kk_KZ	Isakhmet	male
1786	kk_KZ	Isamukambet	male
1787	kk_KZ	Isan	male
1788	kk_KZ	Isatai	male
1789	kk_KZ	Isembek	male
1790	kk_KZ	Ishan	male
1791	kk_KZ	Ishanbai	male
1792	kk_KZ	Ishar	male
1793	kk_KZ	Ishat	male
1794	kk_KZ	Islamkhan	male
1795	kk_KZ	Ismet	male
1796	kk_KZ	Iursulu	female
1797	kk_KZ	Izatima	female
1798	kk_KZ	Izbaisha	female
1799	kk_KZ	Izbas	male
1800	kk_KZ	Izbassar	male
1801	kk_KZ	Izetkhan	female
1802	kk_KZ	Izgilik	male
1803	kk_KZ	Iztai	male
1804	kk_KZ	Kabai	male
1805	kk_KZ	Kabanbai	male
1806	kk_KZ	Kabas	male
1807	kk_KZ	Kabaz	male
1808	kk_KZ	Kabden	male
1809	kk_KZ	Kabdol	male
1810	kk_KZ	Kabi	male
1811	kk_KZ	Kabiba	female
1812	kk_KZ	Kabira	female
1813	kk_KZ	Kabyken	male
1814	kk_KZ	Kabyl	male
1815	kk_KZ	Kabylbek	male
1816	kk_KZ	Kabzhan	male
1817	kk_KZ	Kade	male
1818	kk_KZ	Kadeli	female
1819	kk_KZ	Kaden	female
1820	kk_KZ	Kadima	female
1821	kk_KZ	Kadir	male
1822	kk_KZ	Kadirbai	male
1823	kk_KZ	Kadirbek	male
1824	kk_KZ	Kadirkan	male
1825	kk_KZ	Kadirtai	male
1826	kk_KZ	Kadirzhan	male
1827	kk_KZ	Kadisha	female
1828	kk_KZ	Kadiya	female
1829	kk_KZ	Kadylsha	female
1830	kk_KZ	Kadyr	male
1831	kk_KZ	Kadyrbai	male
1832	kk_KZ	Kadyrbek	male
1833	kk_KZ	Kadyrgali	male
1834	kk_KZ	Kadyrkan	male
1835	kk_KZ	Kadyrkhan	female
1836	kk_KZ	Kadyrsha	female
1837	kk_KZ	Kadyrzhan	male
1838	kk_KZ	Kaidar	male
1839	kk_KZ	Kaiiza	female
1840	kk_KZ	Kainarbai	male
1841	kk_KZ	Kainazar	male
1842	kk_KZ	Kainur	male
1843	kk_KZ	Kainysh	female
1844	kk_KZ	Kairat	male
1845	kk_KZ	Kaisar	male
1846	kk_KZ	Kaisen	male
1847	kk_KZ	Kaisha	female
1848	kk_KZ	Kaiym	male
1849	kk_KZ	Kaiyp	male
1850	kk_KZ	Kaiypbek	male
1851	kk_KZ	Kaiypgali	male
1852	kk_KZ	Kaiypzhan	male
1853	kk_KZ	Kaiyr	male
1854	kk_KZ	Kaiyrbai	male
1855	kk_KZ	Kaiyrbek	male
1856	kk_KZ	Kaiyrbolat	male
1857	kk_KZ	Kaiyrgali	male
1858	kk_KZ	Kaiyrgazy	male
1859	kk_KZ	Kaiyrgeldi	male
1860	kk_KZ	Kaiyrke	male
1861	kk_KZ	Kaiyrken	male
1862	kk_KZ	Kaiyrly	male
1863	kk_KZ	Kaiyrtai	male
1864	kk_KZ	Kaiyrzhamal	female
1865	kk_KZ	Kaiyrzhan	male
1866	kk_KZ	Kaken	male
1867	kk_KZ	Kakharman	male
1868	kk_KZ	Kakima	female
1869	kk_KZ	Kakimtai	male
1870	kk_KZ	Kakimzhan	male
1871	kk_KZ	Kakitai	male
1872	kk_KZ	Kalabai	male
1873	kk_KZ	Kalambai	male
1874	kk_KZ	Kalamkas	female
1875	kk_KZ	Kalampyr	female
1876	kk_KZ	Kalantai	female
1877	kk_KZ	Kalau	male
1878	kk_KZ	Kalausha	male
1879	kk_KZ	Kalbibi	female
1880	kk_KZ	Kalbike	female
1881	kk_KZ	Kaldarbek	male
1882	kk_KZ	Kaldoraz	male
1883	kk_KZ	Kaldybai	male
1884	kk_KZ	Kaldygara	male
1885	kk_KZ	Kali	male
1886	kk_KZ	Kalibek	male
1887	kk_KZ	Kalikhan	male
1888	kk_KZ	Kalila	female
1889	kk_KZ	Kalima	female
1890	kk_KZ	Kalimat	female
1891	kk_KZ	Kalipa	female
1892	kk_KZ	Kalissan	male
1893	kk_KZ	Kalit	male
1894	kk_KZ	Kaliya	female
1895	kk_KZ	Kalka	male
1896	kk_KZ	Kalkaman	male
1897	kk_KZ	Kalken	male
1898	kk_KZ	Kalmakan	male
1899	kk_KZ	Kalmat	male
1900	kk_KZ	Kalmyrza	male
1901	kk_KZ	Kaltai	male
1902	kk_KZ	Kalturgan	female
1903	kk_KZ	Kalua	female
1904	kk_KZ	Kaluan	female
1905	kk_KZ	Kalybai	male
1906	kk_KZ	Kalybek	male
1907	kk_KZ	Kalygul	male
1908	kk_KZ	Kalymbet	male
1909	kk_KZ	Kamal	male
1910	kk_KZ	Kamaliden	male
1911	kk_KZ	Kamaliya	female
1912	kk_KZ	Kamar	male
1913	kk_KZ	Kamariya	female
1914	kk_KZ	Kamarnissa	female
1915	kk_KZ	Kamarsha	female
1916	kk_KZ	Kambar	male
1917	kk_KZ	Kamen	male
1918	kk_KZ	Kamesh	female
1919	kk_KZ	Kamila	female
1920	kk_KZ	Kamilbek	male
1921	kk_KZ	Kamiya	female
1922	kk_KZ	Kamka	female
1923	kk_KZ	Kamkai	female
1924	kk_KZ	Kamshat	female
1925	kk_KZ	Kamys	male
1926	kk_KZ	Kanabek	male
1927	kk_KZ	Kanafiya	male
1928	kk_KZ	Kanagat	male
1929	kk_KZ	Kanai	male
1930	kk_KZ	Kanaibek	male
1931	kk_KZ	Kanapiya	female
1932	kk_KZ	Kanat	male
1933	kk_KZ	Kanatbai	male
1934	kk_KZ	Kanaz	male
1935	kk_KZ	Kanipa	female
1936	kk_KZ	Kanshaiym	female
1937	kk_KZ	Kantgul	female
1938	kk_KZ	Kanybai	male
1939	kk_KZ	Kanysh	male
1940	kk_KZ	Kanziba	female
1941	kk_KZ	Kapan	male
1942	kk_KZ	Kapar	male
1943	kk_KZ	Kapiza	male
1944	kk_KZ	Karabek	male
1945	kk_KZ	Karagoz	female
1946	kk_KZ	Karagul	male
1947	kk_KZ	Karaman	male
1948	kk_KZ	Karas	male
1949	kk_KZ	Karash	male
1950	kk_KZ	Karassai	male
1951	kk_KZ	Karatai	male
1952	kk_KZ	Karazhan	male
1953	kk_KZ	Karboz	male
1954	kk_KZ	Kari	male
1955	kk_KZ	Karim	male
1956	kk_KZ	Karima	female
1957	kk_KZ	Karimzhan	male
1958	kk_KZ	Karina	female
1959	kk_KZ	Karlyga	female
1960	kk_KZ	Karlygash	female
1961	kk_KZ	Karmen	male
1962	kk_KZ	Karmys	male
1963	kk_KZ	Karpyk	male
1964	kk_KZ	Karsen	male
1965	kk_KZ	Karsha	female
1966	kk_KZ	Karshyga	male
1967	kk_KZ	Karzhas	male
1968	kk_KZ	Karzhau	male
1969	kk_KZ	Kashifa	female
1970	kk_KZ	Kashiya	female
1971	kk_KZ	Kaskabas	male
1972	kk_KZ	Kaskei	male
1973	kk_KZ	Kassiman	male
1974	kk_KZ	Kassira	female
1975	kk_KZ	Kassym	male
1976	kk_KZ	Kassymbai	male
1977	kk_KZ	Kassymbek	male
1978	kk_KZ	Kassymkhan	male
1979	kk_KZ	Kassymzhan	male
1980	kk_KZ	Katagan	male
1981	kk_KZ	Katai	male
1982	kk_KZ	Katif	male
1983	kk_KZ	Katima	female
1984	kk_KZ	Katipa	female
1985	kk_KZ	Katira	female
1986	kk_KZ	Katshagul	female
1987	kk_KZ	Kaua	female
1988	kk_KZ	Kaumen	male
1989	kk_KZ	Kaussar	female
1990	kk_KZ	Kauymbai	male
1991	kk_KZ	Kauymbek	male
1992	kk_KZ	Kazakbai	male
1993	kk_KZ	Kazbek	male
1994	kk_KZ	Kazhdenbek	male
1995	kk_KZ	Kazhimbai	male
1996	kk_KZ	Kazhybai	male
1997	kk_KZ	Kazhybek	male
1998	kk_KZ	Kazhygali	male
1999	kk_KZ	Kazhym	male
2000	kk_KZ	Kazhymukan	male
2001	kk_KZ	Kazhymurat	male
2002	kk_KZ	Kazhyr	male
2003	kk_KZ	Kazi	male
2004	kk_KZ	Kazila	female
2005	kk_KZ	Kazima	female
2006	kk_KZ	Kazira	female
2007	kk_KZ	Kaziza	female
2008	kk_KZ	Kazken	male
2009	kk_KZ	Kaztai	male
2010	kk_KZ	Kaztugan	male
2011	kk_KZ	Kazybai	male
2012	kk_KZ	Kazybek	male
2013	kk_KZ	Kazykhan	male
2014	kk_KZ	Kazymbek	male
2015	kk_KZ	Kazymkhan	male
2016	kk_KZ	Kazyna	female
2017	kk_KZ	Kekil	male
2018	kk_KZ	Kekilbai	male
2019	kk_KZ	Kelbet	female
2020	kk_KZ	Keldibai	male
2021	kk_KZ	Kelis	male
2022	kk_KZ	Kelzhan	male
2023	kk_KZ	Kemel	male
2024	kk_KZ	Kemelbai	male
2025	kk_KZ	Kemelbek	male
2026	kk_KZ	Kemen	male
2027	kk_KZ	Kemenger	male
2028	kk_KZ	Kenar	male
2029	kk_KZ	Kenbai	male
2030	kk_KZ	Kendibai	male
2031	kk_KZ	Kenen	male
2032	kk_KZ	Kenenbai	male
2033	kk_KZ	Kenes	male
2034	kk_KZ	Kenesbai	male
2035	kk_KZ	Kenesgul	female
2036	kk_KZ	Keneskhan	female
2037	kk_KZ	Kenshilik	male
2038	kk_KZ	Kenshinbai	male
2039	kk_KZ	Kentbai	male
2040	kk_KZ	Kenzhaly	male
2041	kk_KZ	Kenzhebai	male
2042	kk_KZ	Kenzhebek	male
2043	kk_KZ	Kenzhegali	male
2044	kk_KZ	Kenzhegara	male
2045	kk_KZ	Kenzhegul	male
2046	kk_KZ	Kenzhekei	female
2047	kk_KZ	Kenzhekhan	female
2048	kk_KZ	Kenzhetai	male
2049	kk_KZ	Kerei	male
2050	kk_KZ	Kerim	male
2051	kk_KZ	Kerimbai	male
2052	kk_KZ	Kerimbala	female
2053	kk_KZ	Kerimbek	male
2054	kk_KZ	Kerimsal	female
2055	kk_KZ	Ketei	male
2056	kk_KZ	Khabi	male
2057	kk_KZ	Khabib	male
2058	kk_KZ	Khabiba	female
2059	kk_KZ	Khabibolla	male
2060	kk_KZ	Khadim	male
2061	kk_KZ	Khadisha	female
2062	kk_KZ	Khadiya	female
2063	kk_KZ	Khafiz	male
2064	kk_KZ	Khafiza	female
2065	kk_KZ	Khaidar	male
2066	kk_KZ	Khairiya	female
2067	kk_KZ	Khairolla	male
2068	kk_KZ	Khaisha	female
2069	kk_KZ	Khaittemir	male
2070	kk_KZ	Khakim	male
2071	kk_KZ	Khakimbek	male
2072	kk_KZ	Khakimzhan	male
2073	kk_KZ	Khaknazar	male
2074	kk_KZ	Khalabi	male
2075	kk_KZ	Khalel	male
2076	kk_KZ	Khalid	male
2077	kk_KZ	Khalida	female
2078	kk_KZ	Khalil	male
2079	kk_KZ	Khalila	female
2080	kk_KZ	Khalima	female
2081	kk_KZ	Khalissa	female
2082	kk_KZ	Khalyk	male
2083	kk_KZ	Khalykbai	male
2084	kk_KZ	Khamit	male
2085	kk_KZ	Khammat	male
2086	kk_KZ	Khamza	male
2087	kk_KZ	Khanbek	male
2088	kk_KZ	Khanbolat	male
2089	kk_KZ	Khangali	male
2090	kk_KZ	Khangeldi	male
2091	kk_KZ	Khanifa	female
2092	kk_KZ	Khantemir	male
2093	kk_KZ	Khares	male
2094	kk_KZ	Khassan	male
2095	kk_KZ	Khassen	male
2096	kk_KZ	Khassipa	female
2097	kk_KZ	Khatif	male
2098	kk_KZ	Khatima	female
2099	kk_KZ	Khatip	male
2100	kk_KZ	Khatipa	female
2101	kk_KZ	Khikmet	male
2102	kk_KZ	Khussaiyn	male
2103	kk_KZ	Kibash	male
2104	kk_KZ	Kiikbai	male
2105	kk_KZ	Kilym	male
2106	kk_KZ	Kinar	female
2107	kk_KZ	Kirabai	male
2108	kk_KZ	Kishibek	male
2109	kk_KZ	Kiyakbai	male
2110	kk_KZ	Kiyasbai	male
2111	kk_KZ	Kizat	male
2112	kk_KZ	Klara	female
2113	kk_KZ	Klavdiya	female
2114	kk_KZ	Kobdabai	male
2115	kk_KZ	Kobegen	male
2116	kk_KZ	Kobei	male
2117	kk_KZ	Kobeikhan	male
2118	kk_KZ	Kobeisin	male
2119	kk_KZ	Koben	male
2120	kk_KZ	Kobik	male
2121	kk_KZ	Kobylandy	male
2122	kk_KZ	Kode	male
2123	kk_KZ	Kodek	male
2124	kk_KZ	Kogambai	male
2125	kk_KZ	Kogambek	male
2126	kk_KZ	Koibagar	male
2127	kk_KZ	Koidos	male
2128	kk_KZ	Koilybai	male
2129	kk_KZ	Koishybai	male
2130	kk_KZ	Koishygara	male
2131	kk_KZ	Kokbai	male
2132	kk_KZ	Kokeman	male
2133	kk_KZ	Kolbai	male
2134	kk_KZ	Koldas	male
2135	kk_KZ	Kolganat	male
2136	kk_KZ	Komekbai	male
2137	kk_KZ	Konai	male
2138	kk_KZ	Konak	male
2139	kk_KZ	Konakbai	male
2140	kk_KZ	Konyr	male
2141	kk_KZ	Konyrbai	male
2142	kk_KZ	Konys	male
2143	kk_KZ	Konysbai	male
2144	kk_KZ	Kopbai	male
2145	kk_KZ	Kopzhan	male
2146	kk_KZ	Kopzhassar	male
2147	kk_KZ	Kordabai	male
2148	kk_KZ	Korganbek	male
2149	kk_KZ	Korgasbai	male
2150	kk_KZ	Korik	male
2151	kk_KZ	Korkemzhan	male
2152	kk_KZ	Korlan	female
2153	kk_KZ	Kosbassar	male
2154	kk_KZ	Koshek	male
2155	kk_KZ	Koshen	male
2156	kk_KZ	Koshkarbai	male
2157	kk_KZ	Kosman	male
2158	kk_KZ	Kosmosbek	male
2159	kk_KZ	Kosnazar	male
2160	kk_KZ	Kossai	male
2161	kk_KZ	Kossybai	male
2162	kk_KZ	Kossyn	male
2163	kk_KZ	Kossynbai	male
2164	kk_KZ	Koszhan	male
2165	kk_KZ	Kozha	male
2166	kk_KZ	Kozhabai	male
2167	kk_KZ	Kozhabek	male
2168	kk_KZ	Kozhabergen	male
2169	kk_KZ	Kozhagali	male
2170	kk_KZ	Kozhagul	male
2171	kk_KZ	Kozhak	male
2172	kk_KZ	Kozhakan	male
2173	kk_KZ	Kozhakei	male
2174	kk_KZ	Kozhakhmet	male
2175	kk_KZ	Kozhamkul	male
2176	kk_KZ	Kozhash	male
2177	kk_KZ	Kozhban	male
2178	kk_KZ	Kozhek	male
2179	kk_KZ	Kozhyk	male
2180	kk_KZ	Kozy	male
2181	kk_KZ	Kozybai	male
2182	kk_KZ	Kuan	male
2183	kk_KZ	Kuanbai	male
2184	kk_KZ	Kuandyk	male
2185	kk_KZ	Kuangali	male
2186	kk_KZ	Kuanysh	male
2187	kk_KZ	Kuanyshbai	male
2188	kk_KZ	Kuat	male
2189	kk_KZ	Kuatbek	male
2190	kk_KZ	Kubai	male
2191	kk_KZ	Kuban	male
2192	kk_KZ	Kubara	female
2193	kk_KZ	Kubira	female
2194	kk_KZ	Kudaibergen	male
2195	kk_KZ	Kudas	male
2196	kk_KZ	Kudash	male
2197	kk_KZ	Kudire	male
2198	kk_KZ	Kudiyar	male
2199	kk_KZ	Kudys	male
2200	kk_KZ	Kulai	female
2201	kk_KZ	Kulaikhan	female
2202	kk_KZ	Kulaima	female
2203	kk_KZ	Kulaina	female
2204	kk_KZ	Kulaisha	female
2205	kk_KZ	Kulan	female
2206	kk_KZ	Kulanbai	male
2207	kk_KZ	Kulanda	female
2208	kk_KZ	Kulapan	female
2209	kk_KZ	Kulaparaz	female
2210	kk_KZ	Kulash	female
2211	kk_KZ	Kulassiya	female
2212	kk_KZ	Kulbagila	female
2213	kk_KZ	Kulbagira	female
2214	kk_KZ	Kulbagisha	female
2215	kk_KZ	Kulbakhram	female
2216	kk_KZ	Kulbanu	female
2217	kk_KZ	Kulbara	female
2218	kk_KZ	Kulbarshyn	female
2219	kk_KZ	Kuldana	female
2220	kk_KZ	Kuldara	female
2221	kk_KZ	Kuldariya	female
2222	kk_KZ	Kulen	male
2223	kk_KZ	Kulgaisha	female
2224	kk_KZ	Kulgin	female
2225	kk_KZ	Kulila	female
2226	kk_KZ	Kuliman	female
2227	kk_KZ	Kulimkan	female
2228	kk_KZ	Kulimzhan	female
2229	kk_KZ	Kulipa	female
2230	kk_KZ	Kulira	female
2231	kk_KZ	Kuliya	female
2232	kk_KZ	Kulken	male
2233	kk_KZ	Kulmagambet	male
2234	kk_KZ	Kulmariya	female
2235	kk_KZ	Kulpan	female
2236	kk_KZ	Kulpash	female
2237	kk_KZ	Kulsagila	female
2238	kk_KZ	Kulsara	female
2239	kk_KZ	Kulshai	female
2240	kk_KZ	Kulshaiym	female
2241	kk_KZ	Kulshar	female
2242	kk_KZ	Kulshara	female
2243	kk_KZ	Kulsharkhan	female
2244	kk_KZ	Kulsharuan	female
2245	kk_KZ	Kulshatai	female
2246	kk_KZ	Kulshyn	male
2247	kk_KZ	Kulsin	female
2248	kk_KZ	Kultai	female
2249	kk_KZ	Kulynshak	male
2250	kk_KZ	Kulzabira	female
2251	kk_KZ	Kulzada	female
2252	kk_KZ	Kulzaira	female
2253	kk_KZ	Kulzhami	female
2254	kk_KZ	Kulzhanat	female
2255	kk_KZ	Kulzhauken	female
2256	kk_KZ	Kulzina	female
2257	kk_KZ	Kulzinat	female
2258	kk_KZ	Kulzipa	female
2259	kk_KZ	Kulzira	female
2260	kk_KZ	Kulziya	female
2261	kk_KZ	Kumar	male
2262	kk_KZ	Kumarbek	male
2263	kk_KZ	Kumis	female
2264	kk_KZ	Kumisbai	male
2265	kk_KZ	Kumisbek	male
2266	kk_KZ	Kumisbike	female
2267	kk_KZ	Kumissai	female
2268	kk_KZ	Kunai	female
2269	kk_KZ	Kunaiym	female
2270	kk_KZ	Kunar	male
2271	kk_KZ	Kunbala	female
2272	kk_KZ	Kundar	male
2273	kk_KZ	Kundyz	female
2274	kk_KZ	Kunikei	female
2275	kk_KZ	Kunipi	female
2276	kk_KZ	Kunish	female
2277	kk_KZ	Kuniya	female
2278	kk_KZ	Kunke	female
2279	kk_KZ	Kunsara	female
2280	kk_KZ	Kunsulu	female
2281	kk_KZ	Kuntai	male
2282	kk_KZ	Kuntu	male
2283	kk_KZ	Kuntuar	male
2284	kk_KZ	Kunzhan	female
2285	kk_KZ	Kunzira	female
2286	kk_KZ	Kural	male
2287	kk_KZ	Kuralai	female
2288	kk_KZ	Kuralbai	male
2289	kk_KZ	Kuralbek	male
2290	kk_KZ	Kurban	male
2291	kk_KZ	Kurbangali	male
2292	kk_KZ	Kurbike	female
2293	kk_KZ	Kurman	male
2294	kk_KZ	Kurmanai	male
2295	kk_KZ	Kurmanali	male
2296	kk_KZ	Kurmanbai	male
2297	kk_KZ	Kurmanbek	male
2298	kk_KZ	Kurmangali	male
2299	kk_KZ	Kurmangazy	male
2300	kk_KZ	Kurmantai	male
2301	kk_KZ	Kurmash	male
2302	kk_KZ	Kurmet	male
2303	kk_KZ	Kurtka	female
2304	kk_KZ	Kuryshzhan	male
2305	kk_KZ	Kusbek	male
2306	kk_KZ	Kusman	male
2307	kk_KZ	Kusmangali	male
2308	kk_KZ	Kussaiyn	male
2309	kk_KZ	Kussaiynbek	male
2310	kk_KZ	Kutan	male
2311	kk_KZ	Kutel	male
2312	kk_KZ	Kutkali	male
2313	kk_KZ	Kutkozha	male
2314	kk_KZ	Kuttybai	male
2315	kk_KZ	Kuttybek	male
2316	kk_KZ	Kuttygul	female
2317	kk_KZ	Kuttyk	male
2318	kk_KZ	Kuttykadam	male
2319	kk_KZ	Kuttymbek	male
2320	kk_KZ	Kutzhan	male
2321	kk_KZ	Kydyr	male
2322	kk_KZ	Kydyrali	male
2323	kk_KZ	Kydyrbai	male
2324	kk_KZ	Kydyrbek	male
2325	kk_KZ	Kydyrgali	male
2326	kk_KZ	Kylysh	male
2327	kk_KZ	Kymbat	female
2328	kk_KZ	Kynakul	female
2329	kk_KZ	Kyraubai	male
2330	kk_KZ	Kyrmyzy	female
2331	kk_KZ	Kyrymkul	male
2332	kk_KZ	Kyzgaldak	female
2333	kk_KZ	Kyzykbai	male
2334	kk_KZ	Kyzylkul	female
2335	kk_KZ	Labiba	female
2336	kk_KZ	Laila	female
2337	kk_KZ	Lailim	female
2338	kk_KZ	Lala	female
2339	kk_KZ	Lamziya	female
2340	kk_KZ	Larida	female
2341	kk_KZ	Larissa	female
2342	kk_KZ	Lashker	male
2343	kk_KZ	Lashkerbek	male
2344	kk_KZ	Lashyn	female
2345	kk_KZ	Lassima	female
2346	kk_KZ	Latif	male
2347	kk_KZ	Latifa	female
2348	kk_KZ	Latipa	female
2349	kk_KZ	Laura	female
2350	kk_KZ	Laziza	female
2351	kk_KZ	Lazym	female
2352	kk_KZ	Lazzat	female
2353	kk_KZ	Legiya	female
2354	kk_KZ	Leila	female
2355	kk_KZ	Leker	male
2356	kk_KZ	Lena	female
2357	kk_KZ	Lepes	male
2358	kk_KZ	Lera	female
2359	kk_KZ	Leshker	male
2360	kk_KZ	Liana	female
2361	kk_KZ	Lida	female
2362	kk_KZ	Lidiya	female
2363	kk_KZ	Lila	female
2364	kk_KZ	Liliya	female
2365	kk_KZ	Lira	female
2366	kk_KZ	Liza	female
2367	kk_KZ	Loiza	female
2368	kk_KZ	Lola	female
2369	kk_KZ	Lora	female
2370	kk_KZ	Lorida	female
2371	kk_KZ	Lota	female
2372	kk_KZ	Luiza	female
2373	kk_KZ	Lukpan	male
2374	kk_KZ	Lutfolla	male
2375	kk_KZ	Lyudmila	female
2376	kk_KZ	Lyutsiya	female
2377	kk_KZ	Madakhmet	male
2378	kk_KZ	Madali	male
2379	kk_KZ	Madan	male
2380	kk_KZ	Madazim	male
2381	kk_KZ	Madel	male
2382	kk_KZ	Maden	male
2383	kk_KZ	Madeniet	male
2384	kk_KZ	Madi	male
2385	kk_KZ	Madibala	female
2386	kk_KZ	Madina	female
2387	kk_KZ	Madit	male
2388	kk_KZ	Madiya	female
2389	kk_KZ	Madiyar	male
2390	kk_KZ	Madkhan	male
2391	kk_KZ	Madkhat	male
2392	kk_KZ	Magauiya	male
2393	kk_KZ	Magaz	male
2394	kk_KZ	Magila	female
2395	kk_KZ	Magira	female
2396	kk_KZ	Magisha	female
2397	kk_KZ	Magripa	female
2398	kk_KZ	Magrissa	female
2399	kk_KZ	Magruf	male
2400	kk_KZ	Magymura	female
2401	kk_KZ	Magypar	male
2402	kk_KZ	Magziya	female
2403	kk_KZ	Magzum	male
2404	kk_KZ	Maida	female
2405	kk_KZ	Maidan	male
2406	kk_KZ	Maiemer	male
2407	kk_KZ	Maigul	female
2408	kk_KZ	Maiissa	female
2409	kk_KZ	Maikan	male
2410	kk_KZ	Maiky	male
2411	kk_KZ	Maily	male
2412	kk_KZ	Mailybai	male
2413	kk_KZ	Maiman	male
2414	kk_KZ	Maina	female
2415	kk_KZ	Mainur	female
2416	kk_KZ	Maipa	female
2417	kk_KZ	Maira	female
2418	kk_KZ	Maisa	female
2419	kk_KZ	Maisara	female
2420	kk_KZ	Maisha	female
2421	kk_KZ	Maitan	male
2422	kk_KZ	Maitash	female
2423	kk_KZ	Maitzhan	male
2424	kk_KZ	Maiya	female
2425	kk_KZ	Makabai	male
2426	kk_KZ	Makabyl	male
2427	kk_KZ	Makai	male
2428	kk_KZ	Makan	male
2429	kk_KZ	Makash	male
2430	kk_KZ	Makat	male
2431	kk_KZ	Makatai	male
2432	kk_KZ	Makazhan	male
2433	kk_KZ	Maken	female
2434	kk_KZ	Makfuza	female
2435	kk_KZ	Makhambet	male
2436	kk_KZ	Makhbala	female
2437	kk_KZ	Makhbara	female
2438	kk_KZ	Makhbubi	female
2439	kk_KZ	Makhfura	female
2440	kk_KZ	Makhfuza	female
2441	kk_KZ	Makhinur	female
2442	kk_KZ	Makhmet	male
2443	kk_KZ	Makhmut	male
2444	kk_KZ	Makhu	male
2445	kk_KZ	Makhzada	female
2446	kk_KZ	Makila	female
2447	kk_KZ	Makpal	female
2448	kk_KZ	Maksat	male
2449	kk_KZ	Maksum	male
2450	kk_KZ	Maksuma	female
2451	kk_KZ	Maksut	male
2452	kk_KZ	Maksutbai	male
2453	kk_KZ	Maksym	male
2454	kk_KZ	Maktan	male
2455	kk_KZ	Makulbek	male
2456	kk_KZ	Malbagar	male
2457	kk_KZ	Malbai	male
2458	kk_KZ	Malbek	male
2459	kk_KZ	Maldybai	male
2460	kk_KZ	Malgara	male
2461	kk_KZ	Malgeldi	male
2462	kk_KZ	Malgozy	male
2463	kk_KZ	Malik	male
2464	kk_KZ	Malikaidar	male
2465	kk_KZ	Malike	female
2466	kk_KZ	Malim	male
2467	kk_KZ	Malkar	male
2468	kk_KZ	Malken	male
2469	kk_KZ	Malmak	male
2470	kk_KZ	Maltabar	male
2471	kk_KZ	Malybai	male
2472	kk_KZ	Malzhan	male
2473	kk_KZ	Mamadiyar	male
2474	kk_KZ	Mamai	male
2475	kk_KZ	Maman	male
2476	kk_KZ	Mamassadyk	male
2477	kk_KZ	Mamasseiit	male
2478	kk_KZ	Mamat	male
2479	kk_KZ	Mamazhan	male
2480	kk_KZ	Mambek	male
2481	kk_KZ	Mambet	male
2482	kk_KZ	Mamen	male
2483	kk_KZ	Mamet	male
2484	kk_KZ	Mamila	female
2485	kk_KZ	Mamyk	female
2486	kk_KZ	Mamyr	male
2487	kk_KZ	Mamyrai	male
2488	kk_KZ	Mamyrkhan	male
2489	kk_KZ	Mamyt	male
2490	kk_KZ	Mamytbek	male
2491	kk_KZ	Manabai	male
2492	kk_KZ	Manan	male
2493	kk_KZ	Manap	male
2494	kk_KZ	Manapbai	male
2495	kk_KZ	Manapbek	male
2496	kk_KZ	Manarbek	male
2497	kk_KZ	Manas	male
2498	kk_KZ	Manasbai	male
2499	kk_KZ	Manasbek	male
2500	kk_KZ	Manash	male
2501	kk_KZ	Manau	male
2502	kk_KZ	Mandula	female
2503	kk_KZ	Maneke	male
2504	kk_KZ	Mangytai	male
2505	kk_KZ	Maniga	female
2506	kk_KZ	Manila	female
2507	kk_KZ	Manke	male
2508	kk_KZ	Manshuk	female
2509	kk_KZ	Mansiya	female
2510	kk_KZ	Mansur	male
2511	kk_KZ	Mansura	female
2512	kk_KZ	Mantai	male
2513	kk_KZ	Manuza	female
2514	kk_KZ	Manzila	female
2515	kk_KZ	Manzipa	female
2516	kk_KZ	Manzura	female
2517	kk_KZ	Maply	male
2518	kk_KZ	Mara	female
2519	kk_KZ	Marabai	male
2520	kk_KZ	Maral	female
2521	kk_KZ	Maralbai	male
2522	kk_KZ	Marassul	male
2523	kk_KZ	Marat	male
2524	kk_KZ	Maratbek	male
2525	kk_KZ	Mardan	male
2526	kk_KZ	Maresh	female
2527	kk_KZ	Marfuga	female
2528	kk_KZ	Margaisha	female
2529	kk_KZ	Margarita	female
2530	kk_KZ	Margo	female
2531	kk_KZ	Mariana	female
2532	kk_KZ	Marina	female
2533	kk_KZ	Mariya	female
2534	kk_KZ	Mariyam	female
2535	kk_KZ	Mariyambike	female
2536	kk_KZ	Mariyamkul	female
2537	kk_KZ	Mariyash	female
2538	kk_KZ	Marka	female
2539	kk_KZ	Markai	male
2540	kk_KZ	Markas	male
2541	kk_KZ	Markaska	male
2542	kk_KZ	Markhaba	female
2543	kk_KZ	Markhabai	male
2544	kk_KZ	Markhabat	male
2545	kk_KZ	Markiza	female
2546	kk_KZ	Marlen	male
2547	kk_KZ	Marlena	female
2548	kk_KZ	Marmara	female
2549	kk_KZ	Mars	male
2550	kk_KZ	Marsbek	male
2551	kk_KZ	Marsel	male
2552	kk_KZ	Marshal	male
2553	kk_KZ	Martbek	male
2554	kk_KZ	Marua	female
2555	kk_KZ	Maruaza	female
2556	kk_KZ	Marzhan	female
2557	kk_KZ	Marzhankul	female
2558	kk_KZ	Marzila	female
2559	kk_KZ	Marziya	female
2560	kk_KZ	Mashabai	male
2561	kk_KZ	Mashak	male
2562	kk_KZ	Mashan	male
2563	kk_KZ	Mashei	male
2564	kk_KZ	Mashirbai	male
2565	kk_KZ	Mashkei	male
2566	kk_KZ	Mashkhur	male
2567	kk_KZ	Mashrap	male
2568	kk_KZ	Maskei	male
2569	kk_KZ	Maskut	male
2570	kk_KZ	Massan	male
2571	kk_KZ	Massat	male
2572	kk_KZ	Massaty	female
2573	kk_KZ	Masse	male
2574	kk_KZ	Massimbai	male
2575	kk_KZ	Mastura	female
2576	kk_KZ	Matai	male
2577	kk_KZ	Matakai	male
2578	kk_KZ	Matbi	male
2579	kk_KZ	Maten	female
2580	kk_KZ	Matibai	male
2581	kk_KZ	Matibali	male
2582	kk_KZ	Matibi	male
2583	kk_KZ	Matkarim	male
2584	kk_KZ	Matkassym	male
2585	kk_KZ	Matkerim	male
2586	kk_KZ	Matkhalyk	male
2587	kk_KZ	Matlan	male
2588	kk_KZ	Matluba	female
2589	kk_KZ	Matuza	female
2590	kk_KZ	Matzhan	male
2591	kk_KZ	Mauan	male
2592	kk_KZ	Maue	female
2593	kk_KZ	Mauiya	female
2594	kk_KZ	Mauken	male
2595	kk_KZ	Maukida	female
2596	kk_KZ	Maulen	male
2597	kk_KZ	Maulet	male
2598	kk_KZ	Mauletbai	male
2599	kk_KZ	Maura	female
2600	kk_KZ	Maussymbai	male
2601	kk_KZ	Maussymzhan	female
2602	kk_KZ	Maya	female
2603	kk_KZ	Mazhen	male
2604	kk_KZ	Mazhgul	male
2605	kk_KZ	Mazhila	female
2606	kk_KZ	Mazhit	male
2607	kk_KZ	Mazhyra	male
2608	kk_KZ	Medel	male
2609	kk_KZ	Mederbai	male
2610	kk_KZ	Medet	male
2611	kk_KZ	Medetbai	male
2612	kk_KZ	Medetbek	male
2613	kk_KZ	Medetkhan	male
2614	kk_KZ	Medetnar	male
2615	kk_KZ	Medeu	male
2616	kk_KZ	Medeubek	male
2617	kk_KZ	Medkhat	male
2618	kk_KZ	Meiir	male
2619	kk_KZ	Meiirbek	male
2620	kk_KZ	Meiirkhan	male
2621	kk_KZ	Meiirman	male
2622	kk_KZ	Meiirzhan	female
2623	kk_KZ	Meiiz	female
2624	kk_KZ	Meiizgul	female
2625	kk_KZ	Meiman	male
2626	kk_KZ	Meimankul	female
2627	kk_KZ	Meiram	male
2628	kk_KZ	Meiramgul	female
2629	kk_KZ	Meiramkan	female
2630	kk_KZ	Meirash	female
2631	kk_KZ	Mekebai	male
2632	kk_KZ	Mekemtas	male
2633	kk_KZ	Men	male
2634	kk_KZ	Menash	male
2635	kk_KZ	Mendakhmet	male
2636	kk_KZ	Mendesh	male
2637	kk_KZ	Mendibai	male
2638	kk_KZ	Mendigali	male
2639	kk_KZ	Menlakhmet	male
2640	kk_KZ	Menzhamal	female
2641	kk_KZ	Merei	male
2642	kk_KZ	Mereili	female
2643	kk_KZ	Mergen	male
2644	kk_KZ	Mergenbai	male
2645	kk_KZ	Meruert	female
2646	kk_KZ	Merziya	female
2647	kk_KZ	Mimoza	female
2648	kk_KZ	Minaidar	male
2649	kk_KZ	Minaura	female
2650	kk_KZ	Minipa	female
2651	kk_KZ	Mira	female
2652	kk_KZ	Miras	male
2653	kk_KZ	Mirat	male
2654	kk_KZ	Mirbolat	male
2655	kk_KZ	Mirgali	male
2656	kk_KZ	Mirkarim	male
2657	kk_KZ	Mirkhaidar	male
2658	kk_KZ	Miron	male
2659	kk_KZ	Mirtai	male
2660	kk_KZ	Mirzhan	male
2661	kk_KZ	Miyat	male
2662	kk_KZ	Miyatzhan	male
2663	kk_KZ	Mizam	male
2664	kk_KZ	Mokei	male
2665	kk_KZ	Molbai	male
2666	kk_KZ	Moldabai	male
2667	kk_KZ	Moldabek	male
2668	kk_KZ	Moldagali	male
2669	kk_KZ	Moldakhan	male
2670	kk_KZ	Moldakhmet	male
2671	kk_KZ	Moldan	male
2672	kk_KZ	Moldash	male
2673	kk_KZ	Moldassan	male
2674	kk_KZ	Moldyrakhman	male
2675	kk_KZ	Moltek	male
2676	kk_KZ	Molty	male
2677	kk_KZ	Molybai	male
2678	kk_KZ	Molzhan	male
2679	kk_KZ	Mombek	male
2680	kk_KZ	Momynali	male
2681	kk_KZ	Momysh	male
2682	kk_KZ	Monke	male
2683	kk_KZ	Montai	male
2684	kk_KZ	Moshtai	male
2685	kk_KZ	Moyaz	male
2686	kk_KZ	Mubarak	male
2687	kk_KZ	Mubina	female
2688	kk_KZ	Muka	male
2689	kk_KZ	Mukadil	male
2690	kk_KZ	Mukagali	male
2691	kk_KZ	Mukai	male
2692	kk_KZ	Mukali	male
2693	kk_KZ	Mukamadi	male
2694	kk_KZ	Mukamali	male
2695	kk_KZ	Mukambek	male
2696	kk_KZ	Mukambet	male
2697	kk_KZ	Mukamediya	male
2698	kk_KZ	Mukametgali	male
2699	kk_KZ	Mukametkhan	male
2700	kk_KZ	Mukametzhan	male
2701	kk_KZ	Mukarrama	female
2702	kk_KZ	Mukash	male
2703	kk_KZ	Mukat	male
2704	kk_KZ	Mukatai	male
2705	kk_KZ	Mukazhan	male
2706	kk_KZ	Mukhambetaziz	male
2707	kk_KZ	Mukhambetzhan	male
2708	kk_KZ	Mukhamediyar	male
2709	kk_KZ	Mukhit	male
2710	kk_KZ	Mukhitan	male
2711	kk_KZ	Mukhtar	male
2712	kk_KZ	Mukhtarima	female
2713	kk_KZ	Mukkarima	female
2714	kk_KZ	Muktan	male
2715	kk_KZ	Mukym	male
2716	kk_KZ	Mulipa	female
2717	kk_KZ	Munira	female
2718	kk_KZ	Murabai	male
2719	kk_KZ	Murakan	male
2720	kk_KZ	Muras	male
2721	kk_KZ	Murat	male
2722	kk_KZ	Muratali	male
2723	kk_KZ	Muratbai	male
2724	kk_KZ	Muratbek	male
2725	kk_KZ	Muratkhan	male
2726	kk_KZ	Mursalim	male
2727	kk_KZ	Murseiit	male
2728	kk_KZ	Murtaza	male
2729	kk_KZ	Mushtari	female
2730	kk_KZ	Mussa	male
2731	kk_KZ	Mussabai	male
2732	kk_KZ	Mussabek	male
2733	kk_KZ	Mussagali	male
2734	kk_KZ	Mussagul	male
2735	kk_KZ	Mussaiyn	male
2736	kk_KZ	Mussakan	male
2737	kk_KZ	Mussakhmet	male
2738	kk_KZ	Mussakozha	male
2739	kk_KZ	Mussalim	male
2740	kk_KZ	Mussatai	male
2741	kk_KZ	Mussazhan	male
2742	kk_KZ	Mussen	male
2743	kk_KZ	Mussir	male
2744	kk_KZ	Mussirali	male
2745	kk_KZ	Mussirep	male
2746	kk_KZ	Mustafa	male
2747	kk_KZ	Mustakhib	male
2748	kk_KZ	Mustakhim	male
2749	kk_KZ	Mustan	male
2750	kk_KZ	Mustanai	male
2751	kk_KZ	Mustariz	male
2752	kk_KZ	Mutalip	male
2753	kk_KZ	Mutken	male
2754	kk_KZ	Muza	female
2755	kk_KZ	Muzafar	male
2756	kk_KZ	Mygym	male
2757	kk_KZ	Myktybai	male
2758	kk_KZ	Mynbai	male
2759	kk_KZ	Myrkaidar	male
2760	kk_KZ	Myrkassym	male
2761	kk_KZ	Myrkhaidar	male
2762	kk_KZ	Myrzabai	male
2763	kk_KZ	Myrzabek	male
2764	kk_KZ	Myrzagul	male
2765	kk_KZ	Myrzakhmet	male
2766	kk_KZ	Myrzaly	male
2767	kk_KZ	Myrzamadi	male
2768	kk_KZ	Myrzarakhman	male
2769	kk_KZ	Myrzatai	male
2770	kk_KZ	Myshbai	male
2771	kk_KZ	Myshyrbai	male
2772	kk_KZ	Myskal	female
2773	kk_KZ	Nabi	male
2774	kk_KZ	Nabibolla	male
2775	kk_KZ	Nabiden	male
2776	kk_KZ	Nabiolla	male
2777	kk_KZ	Nabira	female
2778	kk_KZ	Nabiya	female
2779	kk_KZ	Nadir	male
2780	kk_KZ	Nadira	female
2781	kk_KZ	Nadirbai	male
2782	kk_KZ	Nadirbek	male
2783	kk_KZ	Nadiya	female
2784	kk_KZ	Nafissa	female
2785	kk_KZ	Nagashbai	male
2786	kk_KZ	Nagashbek	male
2787	kk_KZ	Nagashybai	male
2788	kk_KZ	Nagi	male
2789	kk_KZ	Nagila	female
2790	kk_KZ	Nagima	female
2791	kk_KZ	Nagisha	female
2792	kk_KZ	Nagiza	female
2793	kk_KZ	Nagmet	male
2794	kk_KZ	Nagym	male
2795	kk_KZ	Nagymbek	male
2796	kk_KZ	Naila	female
2797	kk_KZ	Naimanbai	male
2798	kk_KZ	Naimanbek	male
2799	kk_KZ	Naira	female
2800	kk_KZ	Naizabek	male
2801	kk_KZ	Nakan	male
2802	kk_KZ	Nakyp	male
2803	kk_KZ	Nakysbek	male
2804	kk_KZ	Nakysh	male
2805	kk_KZ	Nalgara	male
2806	kk_KZ	Narbai	male
2807	kk_KZ	Narbek	male
2808	kk_KZ	Narbol	male
2809	kk_KZ	Narbota	male
2810	kk_KZ	Nardan	male
2811	kk_KZ	Nargul	female
2812	kk_KZ	Narik	male
2813	kk_KZ	Narikbai	male
2814	kk_KZ	Narima	female
2815	kk_KZ	Nariman	male
2816	kk_KZ	Narken	male
2817	kk_KZ	Narkes	male
2818	kk_KZ	Narkuat	male
2819	kk_KZ	Narmagambet	male
2820	kk_KZ	Narmambet	male
2821	kk_KZ	Narmat	male
2822	kk_KZ	Narsha	female
2823	kk_KZ	Narshat	male
2824	kk_KZ	Narshyn	male
2825	kk_KZ	Nartai	male
2826	kk_KZ	Nartau	male
2827	kk_KZ	Nartok	male
2828	kk_KZ	Nartu	male
2829	kk_KZ	Narymbet	male
2830	kk_KZ	Narymzhan	male
2831	kk_KZ	Narzan	female
2832	kk_KZ	Narzhan	male
2833	kk_KZ	Nassan	male
2834	kk_KZ	Nassima	female
2835	kk_KZ	Nassyr	male
2836	kk_KZ	Nassyrbai	male
2837	kk_KZ	Natalya	female
2838	kk_KZ	Nauan	male
2839	kk_KZ	Nauat	female
2840	kk_KZ	Naudan	male
2841	kk_KZ	Nauryz	male
2842	kk_KZ	Nauryzbai	male
2843	kk_KZ	Nauryzbek	male
2844	kk_KZ	Nauryzgali	male
2845	kk_KZ	Nausha	female
2846	kk_KZ	Nazar	male
2847	kk_KZ	Nazarali	male
2848	kk_KZ	Nazarbai	male
2849	kk_KZ	Nazarbek	male
2850	kk_KZ	Nazgul	female
2851	kk_KZ	Nazhip	male
2852	kk_KZ	Naziba	female
2853	kk_KZ	Nazipa	female
2854	kk_KZ	Nazir	male
2855	kk_KZ	Nazira	female
2856	kk_KZ	Nazirbek	male
2857	kk_KZ	Nazirvek	male
2858	kk_KZ	Naziya	female
2859	kk_KZ	Naziza	female
2860	kk_KZ	Naztai	male
2861	kk_KZ	Nazygul	female
2862	kk_KZ	Nazym	female
2863	kk_KZ	Nazyrbai	male
2864	kk_KZ	Negim	male
2865	kk_KZ	Nelya	female
2866	kk_KZ	Nessip	male
2867	kk_KZ	Nessipbai	male
2868	kk_KZ	Nessipbek	male
2869	kk_KZ	Nessipzhan	female
2870	kk_KZ	Netali	male
2871	kk_KZ	Netkali	male
2872	kk_KZ	Niet	male
2873	kk_KZ	Nietbai	male
2874	kk_KZ	Nietkali	male
2875	kk_KZ	Nietolla	male
2876	kk_KZ	Nilibai	male
2877	kk_KZ	Nilzhan	female
2878	kk_KZ	Nina	female
2879	kk_KZ	Niyaz	male
2880	kk_KZ	Niyazbek	male
2881	kk_KZ	Niyazmukhambet	male
2882	kk_KZ	Nizam	male
2883	kk_KZ	Nogaibai	male
2884	kk_KZ	Noil	male
2885	kk_KZ	Nokerbek	male
2886	kk_KZ	Noyan	male
2887	kk_KZ	Noyanbai	male
2888	kk_KZ	Nugman	male
2889	kk_KZ	Nugyman	male
2890	kk_KZ	Nur	male
2891	kk_KZ	Nurabai	male
2892	kk_KZ	Nuradil	male
2893	kk_KZ	Nurai	female
2894	kk_KZ	Nuraidar	male
2895	kk_KZ	Nuraina	female
2896	kk_KZ	Nuraisha	female
2897	kk_KZ	Nurak	male
2898	kk_KZ	Nurakhmet	male
2899	kk_KZ	Nurakyn	male
2900	kk_KZ	Nurali	male
2901	kk_KZ	Nuraly	male
2902	kk_KZ	Nuran	male
2903	kk_KZ	Nurash	male
2904	kk_KZ	Nurassyl	female
2905	kk_KZ	Nurbagila	female
2906	kk_KZ	Nurbai	male
2907	kk_KZ	Nurbak	male
2908	kk_KZ	Nurbaken	male
2909	kk_KZ	Nurbanu	female
2910	kk_KZ	Nurbapa	male
2911	kk_KZ	Nurbati	female
2912	kk_KZ	Nurbek	male
2913	kk_KZ	Nurbergen	male
2914	kk_KZ	Nurbibi	female
2915	kk_KZ	Nurbibish	female
2916	kk_KZ	Nurbol	male
2917	kk_KZ	Nurbolat	male
2918	kk_KZ	Nurbolsyn	male
2919	kk_KZ	Nurbossyn	male
2920	kk_KZ	Nurda	female
2921	kk_KZ	Nurdan	male
2922	kk_KZ	Nurdaulet	male
2923	kk_KZ	Nurden	male
2924	kk_KZ	Nurdilda	male
2925	kk_KZ	Nurek	male
2926	kk_KZ	Nurgabyl	male
2927	kk_KZ	Nurgaisa	female
2928	kk_KZ	Nurgaisha	female
2929	kk_KZ	Nurgaiyn	male
2930	kk_KZ	Nurgali	male
2931	kk_KZ	Nurgalipa	female
2932	kk_KZ	Nurgalym	male
2933	kk_KZ	Nurganym	female
2934	kk_KZ	Nurgazy	male
2935	kk_KZ	Nurgedi	male
2936	kk_KZ	Nurgeldi	male
2937	kk_KZ	Nurgissa	male
2938	kk_KZ	Nurgizar	male
2939	kk_KZ	Nurgulsim	female
2940	kk_KZ	Nuri	male
2941	kk_KZ	Nuriddin	male
2942	kk_KZ	Nurikamal	female
2943	kk_KZ	Nurila	female
2944	kk_KZ	Nurima	female
2945	kk_KZ	Nuripa	female
2946	kk_KZ	Nuriya	female
2947	kk_KZ	Nurka	female
2948	kk_KZ	Nurkadil	male
2949	kk_KZ	Nurkaidar	male
2950	kk_KZ	Nurkan	female
2951	kk_KZ	Nurkassym	male
2952	kk_KZ	Nurke	male
2953	kk_KZ	Nurkiya	female
2954	kk_KZ	Nurkiyaz	male
2955	kk_KZ	Nurlai	male
2956	kk_KZ	Nurlan	male
2957	kk_KZ	Nurlas	male
2958	kk_KZ	Nurlat	male
2959	kk_KZ	Nurly	male
2960	kk_KZ	Nurlybai	male
2961	kk_KZ	Nurlybek	male
2962	kk_KZ	Nurlygaiyn	male
2963	kk_KZ	Nurlykan	female
2964	kk_KZ	Nurlykul	female
2965	kk_KZ	Nurlykyz	female
2966	kk_KZ	Nurmagambet	male
2967	kk_KZ	Nurmak	male
2968	kk_KZ	Nurmakan	male
2969	kk_KZ	Nurmambet	male
2970	kk_KZ	Nurman	female
2971	kk_KZ	Nurmukambet	male
2972	kk_KZ	Nurmukhambet	male
2973	kk_KZ	Nurniyaz	male
2974	kk_KZ	Nurpeiis	male
2975	kk_KZ	Nursapa	male
2976	kk_KZ	Nursara	female
2977	kk_KZ	Nursaya	female
2978	kk_KZ	Nurseiit	male
2979	kk_KZ	Nurserke	male
2980	kk_KZ	Nursha	female
2981	kk_KZ	Nurshaiyk	male
2982	kk_KZ	Nurshaiym	female
2983	kk_KZ	Nurshara	female
2984	kk_KZ	Nurshat	female
2985	kk_KZ	Nursipat	female
2986	kk_KZ	Nursiya	female
2987	kk_KZ	Nursovet	male
2988	kk_KZ	Nursultan	male
2989	kk_KZ	Nursulu	female
2990	kk_KZ	Nurtai	male
2991	kk_KZ	Nurtailak	female
2992	kk_KZ	Nurtalap	male
2993	kk_KZ	Nurtan	male
2994	kk_KZ	Nurtas	male
2995	kk_KZ	Nurtaza	male
2996	kk_KZ	Nurtileu	male
2997	kk_KZ	Nurylda	male
2998	kk_KZ	Nurym	male
2999	kk_KZ	Nurymbet	male
3000	kk_KZ	Nurysh	male
3001	kk_KZ	Nurzada	male
3002	kk_KZ	Nurzat	male
3003	kk_KZ	Nurzerek	male
3004	kk_KZ	Nurzhakan	male
3005	kk_KZ	Nurzhamal	female
3006	kk_KZ	Nurzhamila	female
3007	kk_KZ	Nurzhan	male
3008	kk_KZ	Nurzhanat	female
3009	kk_KZ	Nurzhau	male
3010	kk_KZ	Nurzhekei	male
3011	kk_KZ	Nurzhet	male
3012	kk_KZ	Nurzhigit	male
3013	kk_KZ	Nurzhuma	male
3014	kk_KZ	Nurzila	female
3015	kk_KZ	Nurziya	female
3016	kk_KZ	Nuskabai	male
3017	kk_KZ	Nuskar	male
3018	kk_KZ	Nussip	male
3019	kk_KZ	Nussipbek	male
3020	kk_KZ	Nussipkan	male
3021	kk_KZ	Nussipzhan	male
3022	kk_KZ	Nutfolla	male
3023	kk_KZ	Nygmet	male
3024	kk_KZ	Nygmetkali	male
3025	kk_KZ	Nygmetolla	male
3026	kk_KZ	Nygmetzhan	male
3027	kk_KZ	Nyssan	male
3028	kk_KZ	Nyssanaly	male
3029	kk_KZ	Nyssanbai	male
3030	kk_KZ	Obai	male
3031	kk_KZ	Odar	male
3032	kk_KZ	Oibek	male
3033	kk_KZ	Oike	female
3034	kk_KZ	Oily	male
3035	kk_KZ	Oirat	male
3036	kk_KZ	Okan	male
3037	kk_KZ	Okas	male
3038	kk_KZ	Okim	male
3039	kk_KZ	Oksana	female
3040	kk_KZ	Oktem	male
3041	kk_KZ	Oktyabr	male
3042	kk_KZ	Oktyabrina	female
3043	kk_KZ	Olga	female
3044	kk_KZ	Olkebai	male
3045	kk_KZ	Olzhabai	male
3046	kk_KZ	Olzhas	male
3047	kk_KZ	Omar	male
3048	kk_KZ	Omarbai	male
3049	kk_KZ	Omarbek	male
3050	kk_KZ	Omargali	male
3051	kk_KZ	Omargazy	male
3052	kk_KZ	Omarkhan	male
3053	kk_KZ	Omash	male
3054	kk_KZ	Omir	male
3055	kk_KZ	Omirali	male
3056	kk_KZ	Omirbai	male
3057	kk_KZ	Omirbek	male
3058	kk_KZ	Omirgali	male
3059	kk_KZ	Omirgazy	male
3060	kk_KZ	Omirgul	female
3061	kk_KZ	Omirkhan	male
3062	kk_KZ	Omirshe	female
3063	kk_KZ	Omirtai	male
3064	kk_KZ	Omirzak	male
3065	kk_KZ	Onai	male
3066	kk_KZ	Onalbai	male
3067	kk_KZ	Onalbek	male
3068	kk_KZ	Onbai	male
3069	kk_KZ	Ondassyn	male
3070	kk_KZ	Ondiris	male
3071	kk_KZ	Onege	female
3072	kk_KZ	Onerbek	male
3073	kk_KZ	Ongar	male
3074	kk_KZ	Ongarbai	male
3075	kk_KZ	Ongarsyn	male
3076	kk_KZ	Ontai	male
3077	kk_KZ	Opabek	male
3078	kk_KZ	Opazhan	female
3079	kk_KZ	Orak	male
3080	kk_KZ	Orakbai	male
3081	kk_KZ	Oral	male
3082	kk_KZ	Oralbai	male
3083	kk_KZ	Oralbek	male
3084	kk_KZ	Oralkhan	male
3085	kk_KZ	Oraltai	male
3086	kk_KZ	Orash	male
3087	kk_KZ	Orassan	male
3088	kk_KZ	Oraz	male
3089	kk_KZ	Orazai	male
3090	kk_KZ	Orazak	male
3091	kk_KZ	Orazakyn	male
3092	kk_KZ	Orazaly	male
3093	kk_KZ	Orazbai	male
3094	kk_KZ	Orazbek	male
3095	kk_KZ	Orazgeldi	male
3096	kk_KZ	Oraziman	male
3097	kk_KZ	Orazkan	male
3098	kk_KZ	Orazkhan	female
3099	kk_KZ	Orazmukambet	male
3100	kk_KZ	Orazmukhambet	male
3101	kk_KZ	Orazsha	male
3102	kk_KZ	Orazymbet	male
3103	kk_KZ	Orbike	female
3104	kk_KZ	Ordabai	male
3105	kk_KZ	Ordali	male
3106	kk_KZ	Ordan	male
3107	kk_KZ	Oreken	male
3108	kk_KZ	Oren	male
3109	kk_KZ	Orim	male
3110	kk_KZ	Orman	male
3111	kk_KZ	Ormanbai	male
3112	kk_KZ	Ormanshy	male
3113	kk_KZ	Orsha	female
3114	kk_KZ	Orynbai	male
3115	kk_KZ	Orynbek	male
3116	kk_KZ	Oryngali	male
3117	kk_KZ	Orynsha	female
3118	kk_KZ	Orzada	female
3119	kk_KZ	Orziya	female
3120	kk_KZ	Oshakbai	male
3121	kk_KZ	Oshan	male
3122	kk_KZ	Oshar	male
3123	kk_KZ	Oshkar	male
3124	kk_KZ	Oskar	male
3125	kk_KZ	Oskenbai	male
3126	kk_KZ	Ospan	male
3127	kk_KZ	Ospanali	male
3128	kk_KZ	Ospanbai	male
3129	kk_KZ	Ospanbek	male
3130	kk_KZ	Ospangali	male
3131	kk_KZ	Ospankhan	male
3132	kk_KZ	Ospantai	male
3133	kk_KZ	Ossan	male
3134	kk_KZ	Osser	male
3135	kk_KZ	Osserbai	male
3136	kk_KZ	Osserbek	male
3137	kk_KZ	Ostemir	male
3138	kk_KZ	Ostrat	male
3139	kk_KZ	Otan	male
3140	kk_KZ	Otar	male
3141	kk_KZ	Otarbai	male
3142	kk_KZ	Otebai	male
3143	kk_KZ	Otegali	male
3144	kk_KZ	Otegen	male
3145	kk_KZ	Otemagambet	male
3146	kk_KZ	Otembai	male
3147	kk_KZ	Otemgali	male
3148	kk_KZ	Otemis	male
3149	kk_KZ	Otetileu	male
3150	kk_KZ	Otezhan	male
3151	kk_KZ	Ozarbek	male
3152	kk_KZ	Ozariya	female
3153	kk_KZ	Ozat	male
3154	kk_KZ	Ozbek	male
3155	kk_KZ	Ozenbai	male
3156	kk_KZ	Ozharbai	male
3157	kk_KZ	Ozhet	male
3158	kk_KZ	Ozhken	female
3159	kk_KZ	Ozipa	female
3160	kk_KZ	Paluan	male
3161	kk_KZ	Paluangali	male
3162	kk_KZ	Palym	male
3163	kk_KZ	Palymbet	male
3164	kk_KZ	Pana	female
3165	kk_KZ	Panabek	male
3166	kk_KZ	Panagul	female
3167	kk_KZ	Panash	male
3168	kk_KZ	Parmen	male
3169	kk_KZ	Parsat	male
3170	kk_KZ	Paryk	male
3171	kk_KZ	Parzan	female
3172	kk_KZ	Pazyl	male
3173	kk_KZ	Pazylbek	male
3174	kk_KZ	Perdebek	male
3175	kk_KZ	Perizat	female
3176	kk_KZ	Peruziya	female
3177	kk_KZ	Pirali	male
3178	kk_KZ	Pirnazar	male
3179	kk_KZ	Polymbet	male
3180	kk_KZ	Rabat	male
3181	kk_KZ	Rabiga	female
3182	kk_KZ	Rabiya	female
3183	kk_KZ	Rabkat	male
3184	kk_KZ	Radik	male
3185	kk_KZ	Radzh	male
3186	kk_KZ	Rafik	male
3187	kk_KZ	Rafikha	female
3188	kk_KZ	Rafil	male
3189	kk_KZ	Rai	male
3190	kk_KZ	Raibai	male
3191	kk_KZ	Raibek	male
3192	kk_KZ	Raigul	female
3193	kk_KZ	Raikhan	female
3194	kk_KZ	Raikul	female
3195	kk_KZ	Rail	male
3196	kk_KZ	Raima	female
3197	kk_KZ	Rainur	male
3198	kk_KZ	Raisa	female
3199	kk_KZ	Raisha	female
3200	kk_KZ	Raiymbek	male
3201	kk_KZ	Raiys	male
3202	kk_KZ	Raiyskali	male
3203	kk_KZ	Rakap	male
3204	kk_KZ	Rakat	male
3205	kk_KZ	Rakhila	female
3206	kk_KZ	Rakhima	female
3207	kk_KZ	Rakhiya	female
3208	kk_KZ	Rakhman	male
3209	kk_KZ	Rakhmankul	male
3210	kk_KZ	Rakhmet	male
3211	kk_KZ	Rakhmetolla	male
3212	kk_KZ	Rakhmettolla	male
3213	kk_KZ	Rakym	male
3214	kk_KZ	Rakymbai	male
3215	kk_KZ	Rakymbek	male
3216	kk_KZ	Rakymbergen	male
3217	kk_KZ	Rakymgali	male
3218	kk_KZ	Rakymzhan	male
3219	kk_KZ	Rakysh	male
3220	kk_KZ	Raman	male
3221	kk_KZ	Ramazan	male
3222	kk_KZ	Ramiz	male
3223	kk_KZ	Ramziya	female
3224	kk_KZ	Raniya	female
3225	kk_KZ	Rapiya	female
3226	kk_KZ	Rashida	female
3227	kk_KZ	Rashila	female
3228	kk_KZ	Rashina	female
3229	kk_KZ	Rashit	male
3230	kk_KZ	Rassima	female
3231	kk_KZ	Rassul	male
3232	kk_KZ	Rassulbek	male
3233	kk_KZ	Rauan	male
3234	kk_KZ	Rauf	male
3235	kk_KZ	Rauza	female
3236	kk_KZ	Raya	female
3237	kk_KZ	Razak	male
3238	kk_KZ	Razbai	male
3239	kk_KZ	Razgul	female
3240	kk_KZ	Razida	female
3241	kk_KZ	Razila	female
3242	kk_KZ	Razima	female
3243	kk_KZ	Razita	female
3244	kk_KZ	Raziya	female
3245	kk_KZ	Raziza	female
3246	kk_KZ	Rena	female
3247	kk_KZ	Renat	male
3248	kk_KZ	Renata	female
3249	kk_KZ	Rika	female
3250	kk_KZ	Rimma	female
3251	kk_KZ	Rimmat	female
3252	kk_KZ	Rishat	male
3253	kk_KZ	Rita	female
3254	kk_KZ	Riza	male
3255	kk_KZ	Rizabek	male
3256	kk_KZ	Romat	female
3257	kk_KZ	Roza	female
3258	kk_KZ	Rozaliya	female
3259	kk_KZ	Rufa	female
3260	kk_KZ	Rufiya	female
3261	kk_KZ	Rukhigul	female
3262	kk_KZ	Rukhiya	female
3263	kk_KZ	Ruslan	male
3264	kk_KZ	Ruslana	female
3265	kk_KZ	Rustem	male
3266	kk_KZ	Rustembek	male
3267	kk_KZ	Rysbek	male
3268	kk_KZ	Ryskeldi	male
3269	kk_KZ	Sabanshy	male
3270	kk_KZ	Sabatai	male
3271	kk_KZ	Sabaz	male
3272	kk_KZ	Sabazbek	male
3273	kk_KZ	Sabiga	female
3274	kk_KZ	Sabigat	male
3275	kk_KZ	Sabila	female
3276	kk_KZ	Sabira	female
3277	kk_KZ	Sabit	male
3278	kk_KZ	Sabitbek	male
3279	kk_KZ	Sabitkhan	male
3280	kk_KZ	Sabyr	male
3281	kk_KZ	Sabyrbek	male
3282	kk_KZ	Sabyrkhan	male
3283	kk_KZ	Sabyrkul	female
3284	kk_KZ	Sabyrzhan	male
3285	kk_KZ	Sadan	male
3286	kk_KZ	Sadben	male
3287	kk_KZ	Saden	male
3288	kk_KZ	Sadi	male
3289	kk_KZ	Sadibek	male
3290	kk_KZ	Sadida	female
3291	kk_KZ	Sadu	male
3292	kk_KZ	Saduakas	male
3293	kk_KZ	Sadybai	male
3294	kk_KZ	Sadyk	male
3295	kk_KZ	Sadykbai	male
3296	kk_KZ	Sadykbek	male
3297	kk_KZ	Sadyr	male
3298	kk_KZ	Sadyrbai	male
3299	kk_KZ	Sadyrbek	male
3300	kk_KZ	Safa	male
3301	kk_KZ	Safi	male
3302	kk_KZ	Safuan	male
3303	kk_KZ	Safura	female
3304	kk_KZ	Sagadai	female
3305	kk_KZ	Sagadat	male
3306	kk_KZ	Sagadi	male
3307	kk_KZ	Sagai	male
3308	kk_KZ	Sagat	male
3309	kk_KZ	Sagatai	male
3310	kk_KZ	Sagatbai	male
3311	kk_KZ	Sagatbek	male
3312	kk_KZ	Sagdi	male
3313	kk_KZ	Sagi	male
3314	kk_KZ	Sagida	female
3315	kk_KZ	Sagidolla	male
3316	kk_KZ	Sagila	female
3317	kk_KZ	Sagira	female
3318	kk_KZ	Sagit	male
3319	kk_KZ	Sagiya	female
3320	kk_KZ	Sagym	male
3321	kk_KZ	Sagyn	male
3322	kk_KZ	Sagynai	male
3323	kk_KZ	Sagyndyk	male
3324	kk_KZ	Sagyngali	male
3325	kk_KZ	Sagyntai	male
3326	kk_KZ	Sagyr	male
3327	kk_KZ	Sagyrbai	male
3328	kk_KZ	Saibak	male
3329	kk_KZ	Saida	female
3330	kk_KZ	Saidar	male
3331	kk_KZ	Saiki	male
3332	kk_KZ	Sailar	male
3333	kk_KZ	Sailau	male
3334	kk_KZ	Sailaubai	male
3335	kk_KZ	Sailaugul	female
3336	kk_KZ	Saimassai	male
3337	kk_KZ	Sainazar	male
3338	kk_KZ	Saira	female
3339	kk_KZ	Sairambai	male
3340	kk_KZ	Sairan	male
3341	kk_KZ	Sairanbai	male
3342	kk_KZ	Sait	male
3343	kk_KZ	Saiym	male
3344	kk_KZ	Saiyn	male
3345	kk_KZ	Saiynbek	male
3346	kk_KZ	Saiyp	male
3347	kk_KZ	Saiypbek	male
3348	kk_KZ	Saiypnazar	male
3349	kk_KZ	Sakap	female
3350	kk_KZ	Saken	male
3351	kk_KZ	Sakhi	male
3352	kk_KZ	Sakhima	female
3353	kk_KZ	Saktan	male
3354	kk_KZ	Saktar	male
3355	kk_KZ	Sakyman	female
3356	kk_KZ	Sakyp	female
3357	kk_KZ	Sakypzhamal	female
3358	kk_KZ	Sakysh	female
3359	kk_KZ	Salamat	male
3360	kk_KZ	Salauat	male
3361	kk_KZ	Salgara	male
3362	kk_KZ	Sali	male
3363	kk_KZ	Salikha	female
3364	kk_KZ	Salim	male
3365	kk_KZ	Salima	female
3366	kk_KZ	Saliman	female
3367	kk_KZ	Salimbai	male
3368	kk_KZ	Salimbek	male
3369	kk_KZ	Salimzhan	male
3370	kk_KZ	Salken	male
3371	kk_KZ	Salmen	male
3372	kk_KZ	Saltai	male
3373	kk_KZ	Saltanat	female
3374	kk_KZ	Salyk	male
3375	kk_KZ	Salykbai	male
3376	kk_KZ	Salymbai	male
3377	kk_KZ	Samal	female
3378	kk_KZ	Samalkhan	female
3379	kk_KZ	Samarat	male
3380	kk_KZ	Samarbai	male
3381	kk_KZ	Samat	male
3382	kk_KZ	Samatai	male
3383	kk_KZ	Samen	male
3384	kk_KZ	Samet	male
3385	kk_KZ	Samga	male
3386	kk_KZ	Sami	male
3387	kk_KZ	Samiya	female
3388	kk_KZ	Samurat	male
3389	kk_KZ	San	female
3390	kk_KZ	Sanabai	male
3391	kk_KZ	Sanamai	female
3392	kk_KZ	Sanat	male
3393	kk_KZ	Sanbai	male
3394	kk_KZ	Sandugash	female
3395	kk_KZ	Sandybai	male
3396	kk_KZ	Sangerei	male
3397	kk_KZ	Sani	male
3398	kk_KZ	Sanida	female
3399	kk_KZ	Sanimai	female
3400	kk_KZ	Sanipa	female
3401	kk_KZ	Saniya	female
3402	kk_KZ	Sansyzbai	male
3403	kk_KZ	Santai	male
3404	kk_KZ	Sanzhar	male
3405	kk_KZ	Sapa	male
3406	kk_KZ	Sapabai	male
3407	kk_KZ	Sapabek	male
3408	kk_KZ	Sapak	male
3409	kk_KZ	Sapar	male
3410	kk_KZ	Saparbai	male
3411	kk_KZ	Saparbek	male
3412	kk_KZ	Sapargali	male
3413	kk_KZ	Sapi	male
3414	kk_KZ	Sapina	female
3415	kk_KZ	Sarbala	male
3416	kk_KZ	Sardar	male
3417	kk_KZ	Sardarbek	male
3418	kk_KZ	Sargaska	male
3419	kk_KZ	Sargozha	male
3420	kk_KZ	Sari	male
3421	kk_KZ	Sariya	female
3422	kk_KZ	Sarken	male
3423	kk_KZ	Sarkyt	female
3424	kk_KZ	Sarkytgul	female
3425	kk_KZ	Sarman	male
3426	kk_KZ	Sarmantai	male
3427	kk_KZ	Sarmat	male
3428	kk_KZ	Sarsek	male
3429	kk_KZ	Sarsekei	male
3430	kk_KZ	Sarsen	male
3431	kk_KZ	Sarsenbai	male
3432	kk_KZ	Sarsenbi	male
3433	kk_KZ	Sartai	male
3434	kk_KZ	Saruar	female
3435	kk_KZ	Sary	male
3436	kk_KZ	Sarybai	male
3437	kk_KZ	Sarybas	male
3438	kk_KZ	Saryk	male
3439	kk_KZ	Saryn	male
3440	kk_KZ	Sarzhan	male
3441	kk_KZ	Sassan	male
3442	kk_KZ	Sat	male
3443	kk_KZ	Satai	male
3444	kk_KZ	Satbai	male
3445	kk_KZ	Satbek	male
3446	kk_KZ	Saten	female
3447	kk_KZ	Satibek	male
3448	kk_KZ	Satim	male
3449	kk_KZ	Satke	male
3450	kk_KZ	Sattar	male
3451	kk_KZ	Sattibai	male
3452	kk_KZ	Sattigul	male
3453	kk_KZ	Satybaldy	male
3454	kk_KZ	Satybek	male
3455	kk_KZ	Satymzhan	male
3456	kk_KZ	Satzhan	male
3457	kk_KZ	Saugabai	male
3458	kk_KZ	Sauir	male
3459	kk_KZ	Sauirbai	male
3460	kk_KZ	Sauirbek	male
3461	kk_KZ	Saule	female
3462	kk_KZ	Saulebai	male
3463	kk_KZ	Saulebek	male
3464	kk_KZ	Sauran	male
3465	kk_KZ	Sauranbai	male
3466	kk_KZ	Sauranbek	male
3467	kk_KZ	Sauryk	male
3468	kk_KZ	Sauyk	male
3469	kk_KZ	Sauyt	male
3470	kk_KZ	Sauytbai	male
3471	kk_KZ	Saya	male
3472	kk_KZ	Sayan	male
3473	kk_KZ	Sayatkan	male
3474	kk_KZ	Sayazhan	male
3475	kk_KZ	Sazhida	female
3476	kk_KZ	Seidakhmet	male
3477	kk_KZ	Seidali	male
3478	kk_KZ	Seidaz	male
3479	kk_KZ	Seidazym	male
3480	kk_KZ	Seidekhan	male
3481	kk_KZ	Seidilda	male
3482	kk_KZ	Seidimbek	male
3483	kk_KZ	Seidin	male
3484	kk_KZ	Seidolla	male
3485	kk_KZ	Seidrakhman	male
3486	kk_KZ	Seiduali	male
3487	kk_KZ	Seifolla	male
3488	kk_KZ	Seiil	male
3489	kk_KZ	Seiilbek	male
3490	kk_KZ	Seiilzhan	male
3491	kk_KZ	Seiit	male
3492	kk_KZ	Seiitali	male
3493	kk_KZ	Seiitbattal	male
3494	kk_KZ	Seiitbek	male
3495	kk_KZ	Seiitkazy	male
3496	kk_KZ	Seiitkemel	male
3497	kk_KZ	Seiitkhan	male
3498	kk_KZ	Seiitmet	male
3499	kk_KZ	Seiitmurat	male
3500	kk_KZ	Seiitnazar	male
3501	kk_KZ	Seiitzhan	male
3502	kk_KZ	Seisenbai	male
3503	kk_KZ	Seisenbek	male
3504	kk_KZ	Seitek	male
3505	kk_KZ	Seiten	male
3506	kk_KZ	Seitimbet	male
3507	kk_KZ	Seken	male
3508	kk_KZ	Seksenbai	male
3509	kk_KZ	Sembai	male
3510	kk_KZ	Sembek	male
3511	kk_KZ	Sembet	male
3512	kk_KZ	Sembi	male
3513	kk_KZ	Sementei	male
3514	kk_KZ	Sengirbai	male
3515	kk_KZ	Senim	male
3516	kk_KZ	Serali	male
3517	kk_KZ	Serbota	male
3518	kk_KZ	Sergali	male
3519	kk_KZ	Sergaly	male
3520	kk_KZ	Sergazy	male
3521	kk_KZ	Serik	male
3522	kk_KZ	Serikali	male
3523	kk_KZ	Serikbai	male
3524	kk_KZ	Serikbek	male
3525	kk_KZ	Serikbol	male
3526	kk_KZ	Serikkali	male
3527	kk_KZ	Serikzhan	male
3528	kk_KZ	Serke	male
3529	kk_KZ	Serkebai	male
3530	kk_KZ	Sermagambet	male
3531	kk_KZ	Sertai	male
3532	kk_KZ	Serzhan	male
3533	kk_KZ	Sezim	male
3534	kk_KZ	Shabai	male
3535	kk_KZ	Shabak	male
3536	kk_KZ	Shabal	female
3537	kk_KZ	Shabdan	male
3538	kk_KZ	Shaden	male
3539	kk_KZ	Shadi	male
3540	kk_KZ	Shadyman	male
3541	kk_KZ	Shafiga	female
3542	kk_KZ	Shafik	male
3543	kk_KZ	Shafikh	male
3544	kk_KZ	Shafkat	male
3545	kk_KZ	Shafkhat	male
3546	kk_KZ	Shagila	female
3547	kk_KZ	Shagyr	male
3548	kk_KZ	Shaibala	female
3549	kk_KZ	Shaiban	male
3550	kk_KZ	Shaibek	male
3551	kk_KZ	Shaidakhmet	male
3552	kk_KZ	Shaidar	male
3553	kk_KZ	Shaidarbek	male
3554	kk_KZ	Shaidolla	male
3555	kk_KZ	Shaigul	female
3556	kk_KZ	Shaiken	male
3557	kk_KZ	Shaikhan	male
3558	kk_KZ	Shaikhy	male
3559	kk_KZ	Shaimerden	male
3560	kk_KZ	Shainur	male
3561	kk_KZ	Shaizada	female
3562	kk_KZ	Shaizhan	male
3563	kk_KZ	Shakabai	male
3564	kk_KZ	Shakarim	male
3565	kk_KZ	Shaken	male
3566	kk_KZ	Shakhakhmet	male
3567	kk_KZ	Shakhaman	male
3568	kk_KZ	Shakhan	male
3569	kk_KZ	Shakhar	male
3570	kk_KZ	Shakharbai	male
3571	kk_KZ	Shakhida	female
3572	kk_KZ	Shakhiya	female
3573	kk_KZ	Shakhmardan	male
3574	kk_KZ	Shakhmukhambet	male
3575	kk_KZ	Shakhmurat	male
3576	kk_KZ	Shakhnazar	male
3577	kk_KZ	Shakhzada	female
3578	kk_KZ	Shakir	male
3579	kk_KZ	Shakira	female
3580	kk_KZ	Shakirbek	male
3581	kk_KZ	Shakiza	female
3582	kk_KZ	Shakizat	female
3583	kk_KZ	Shakura	female
3584	kk_KZ	Shalabai	male
3585	kk_KZ	Shalakhmet	male
3586	kk_KZ	Shaldibek	male
3587	kk_KZ	Shaldybai	male
3588	kk_KZ	Shalgez	male
3589	kk_KZ	Shalipa	female
3590	kk_KZ	Shalkar	male
3591	kk_KZ	Shalkarbai	male
3592	kk_KZ	Sham	male
3593	kk_KZ	Shamat	male
3594	kk_KZ	Shambyl	male
3595	kk_KZ	Shamel	male
3596	kk_KZ	Shamen	male
3597	kk_KZ	Shamgon	male
3598	kk_KZ	Shamgul	female
3599	kk_KZ	Shami	male
3600	kk_KZ	Shamil	male
3601	kk_KZ	Shamis	male
3602	kk_KZ	Shamken	male
3603	kk_KZ	Shamsha	female
3604	kk_KZ	Shamshat	male
3605	kk_KZ	Shamshi	male
3606	kk_KZ	Shamshiya	female
3607	kk_KZ	Shamsiya	female
3608	kk_KZ	Shamurat	male
3609	kk_KZ	Shamzhan	male
3610	kk_KZ	Shangytbai	male
3611	kk_KZ	Shani	male
3612	kk_KZ	Shaniyat	male
3613	kk_KZ	Shapagat	male
3614	kk_KZ	Shapai	male
3615	kk_KZ	Shapak	male
3616	kk_KZ	Shapi	male
3617	kk_KZ	Shapshak	male
3618	kk_KZ	Shara-Shyryngul	female
3619	kk_KZ	Shara	female
3620	kk_KZ	Sharabas	male
3621	kk_KZ	Sharapa	female
3622	kk_KZ	Sharapiya	female
3623	kk_KZ	Sharbanu	female
3624	kk_KZ	Sharbat	female
3625	kk_KZ	Sharip	male
3626	kk_KZ	Sharipa	female
3627	kk_KZ	Sharipbai	male
3628	kk_KZ	Sharipbek	male
3629	kk_KZ	Sharipkhan	male
3630	kk_KZ	Sharizat	male
3631	kk_KZ	Shartai	male
3632	kk_KZ	Sharybai	male
3633	kk_KZ	Sharykbek	male
3634	kk_KZ	Shashubai	male
3635	kk_KZ	Shatan	male
3636	kk_KZ	Shatkerim	male
3637	kk_KZ	Shattygul	female
3638	kk_KZ	Shattyk	male
3639	kk_KZ	Shauken	male
3640	kk_KZ	Shaukenbai	male
3641	kk_KZ	Shauzhan	male
3642	kk_KZ	Shayakhmet	male
3643	kk_KZ	Shazhabek	male
3644	kk_KZ	Shege	male
3645	kk_KZ	Shegebai	male
3646	kk_KZ	Sheker	female
3647	kk_KZ	Shekerbek	male
3648	kk_KZ	Shektibai	male
3649	kk_KZ	Sher	male
3650	kk_KZ	Sherali	male
3651	kk_KZ	Shergali	male
3652	kk_KZ	Sheri	male
3653	kk_KZ	Sherimbek	male
3654	kk_KZ	Sherkhan	male
3655	kk_KZ	Shermukhambet	male
3656	kk_KZ	Sherniyaz	male
3657	kk_KZ	Sherubai	male
3658	kk_KZ	Shildebai	male
3659	kk_KZ	Shiyab	male
3660	kk_KZ	Shoibek	male
3661	kk_KZ	Shoiman	male
3662	kk_KZ	Shokan	male
3663	kk_KZ	Shoky	male
3664	kk_KZ	Shokyr	male
3665	kk_KZ	Sholan	male
3666	kk_KZ	Sholman	male
3667	kk_KZ	Sholpan	female
3668	kk_KZ	Sholpanai	female
3669	kk_KZ	Sholpanbai	male
3670	kk_KZ	Sholpanbek	male
3671	kk_KZ	Shombal	male
3672	kk_KZ	Shombek	male
3673	kk_KZ	Shon	male
3674	kk_KZ	Shona	male
3675	kk_KZ	Shonbai	male
3676	kk_KZ	Shopan	male
3677	kk_KZ	Shora	male
3678	kk_KZ	Shorabai	male
3679	kk_KZ	Shorabek	male
3680	kk_KZ	Shorman	male
3681	kk_KZ	Shortanbai	male
3682	kk_KZ	Shota	male
3683	kk_KZ	Shotai	male
3684	kk_KZ	Shotan	male
3685	kk_KZ	Shotbai	male
3686	kk_KZ	Shozhe	male
3687	kk_KZ	Shuga	female
3688	kk_KZ	Shukir	male
3689	kk_KZ	Shukirali	male
3690	kk_KZ	Shukirbai	male
3691	kk_KZ	Shukirbek	male
3692	kk_KZ	Shygai	male
3693	kk_KZ	Shyganak	male
3694	kk_KZ	Shyman	male
3695	kk_KZ	Shymyr	male
3696	kk_KZ	Shynaly	male
3697	kk_KZ	Shynar	female
3698	kk_KZ	Shynargul	female
3699	kk_KZ	Shynassyl	male
3700	kk_KZ	Shynbolat	male
3701	kk_KZ	Shyndaly	male
3702	kk_KZ	Shyndaulet	male
3703	kk_KZ	Shyngali	male
3704	kk_KZ	Shyngys	male
3705	kk_KZ	Shyntas	male
3706	kk_KZ	Shyntemir	male
3707	kk_KZ	Shyntileu	male
3708	kk_KZ	Shynybai	male
3709	kk_KZ	Shynybek	male
3710	kk_KZ	Shyrai	female
3711	kk_KZ	Shyraigul	female
3712	kk_KZ	Shyrakbek	male
3713	kk_KZ	Shyrgali	male
3714	kk_KZ	Shyryn	female
3715	kk_KZ	Shyryngul	female
3716	kk_KZ	Simak	male
3717	kk_KZ	Siran	male
3718	kk_KZ	Sirazh	male
3719	kk_KZ	Siyazbai	male
3720	kk_KZ	Sofiya	female
3721	kk_KZ	Sokpakbai	male
3722	kk_KZ	Sokrat	male
3723	kk_KZ	Soldatbek	male
3724	kk_KZ	Soltanai	male
3725	kk_KZ	Solty	male
3726	kk_KZ	Soltybai	male
3727	kk_KZ	Sombel	male
3728	kk_KZ	Sonya	female
3729	kk_KZ	Sovet	male
3730	kk_KZ	Sovetbek	male
3731	kk_KZ	Sovetiyar	male
3732	kk_KZ	Sovetzhan	male
3733	kk_KZ	Stambaky	male
3734	kk_KZ	Stambek	male
3735	kk_KZ	Sugir	male
3736	kk_KZ	Sugirbai	male
3737	kk_KZ	Suieu	male
3738	kk_KZ	Suiimkhan	female
3739	kk_KZ	Suiin	male
3740	kk_KZ	Suiinbai	male
3741	kk_KZ	Suiinbala	female
3742	kk_KZ	Suiinshali	male
3743	kk_KZ	Suirik	female
3744	kk_KZ	Sukhambai	male
3745	kk_KZ	Sukhamberdi	male
3746	kk_KZ	Suleimen	male
3747	kk_KZ	Sultan	male
3748	kk_KZ	Sultanbai	male
3749	kk_KZ	Sultanbek	male
3750	kk_KZ	Sultangali	male
3751	kk_KZ	Sultangazy	male
3752	kk_KZ	Sultangeldi	male
3753	kk_KZ	Sultaniya	male
3754	kk_KZ	Sultanmurat	male
3755	kk_KZ	Sulu	female
3756	kk_KZ	Suluke	female
3757	kk_KZ	Sulukhan	female
3758	kk_KZ	Suluman	female
3759	kk_KZ	Sulushash	female
3760	kk_KZ	Sumbebai	male
3761	kk_KZ	Sumbil	female
3762	kk_KZ	Sundet	male
3763	kk_KZ	Sunkar	male
3764	kk_KZ	Suragan	male
3765	kk_KZ	Sutkenzhe	female
3766	kk_KZ	Suttibai	male
3767	kk_KZ	Sveta	female
3768	kk_KZ	Svetlana	female
3769	kk_KZ	Sybanbai	male
3770	kk_KZ	Sybankul	male
3771	kk_KZ	Sydyk	male
3772	kk_KZ	Sygai	male
3773	kk_KZ	Syikym	male
3774	kk_KZ	Syiyk	male
3775	kk_KZ	Sylan	male
3776	kk_KZ	Symaiyl	male
3777	kk_KZ	Symak	male
3778	kk_KZ	Symakhan	male
3779	kk_KZ	Symat	male
3780	kk_KZ	Symatai	male
3781	kk_KZ	Symbat	female
3782	kk_KZ	Syndybai	male
3783	kk_KZ	Syndybala	female
3784	kk_KZ	Sypatai	male
3785	kk_KZ	Syrazhy	male
3786	kk_KZ	Syrbai	male
3787	kk_KZ	Syrga	female
3788	kk_KZ	Syrgabai	male
3789	kk_KZ	Syrgabek	male
3790	kk_KZ	Syrgaly	female
3791	kk_KZ	Syrlybai	male
3792	kk_KZ	Syrlybek	male
3793	kk_KZ	Syrmukhambet	male
3794	kk_KZ	Syrym	male
3795	kk_KZ	Syrymbet	male
3796	kk_KZ	Syzdyk	male
3797	kk_KZ	Tabar	male
3798	kk_KZ	Tabat	male
3799	kk_KZ	Tabiba	female
3800	kk_KZ	Tabila	female
3801	kk_KZ	Tabiya	female
3802	kk_KZ	Tabyl	male
3803	kk_KZ	Tabyldy	male
3804	kk_KZ	Tabylgan	male
3805	kk_KZ	Tabys	male
3806	kk_KZ	Tadgatbek	male
3807	kk_KZ	Tagai	male
3808	kk_KZ	Tagash	male
3809	kk_KZ	Taibala	female
3810	kk_KZ	Taibek	male
3811	kk_KZ	Taiken	female
3812	kk_KZ	Tailak	male
3813	kk_KZ	Tailambek	male
3814	kk_KZ	Taiman	male
3815	kk_KZ	Taimas	male
3816	kk_KZ	Taishat	male
3817	kk_KZ	Taishyk	male
3818	kk_KZ	Taiymbet	male
3819	kk_KZ	Taiyr	male
3820	kk_KZ	Taizhan	male
3821	kk_KZ	Taken	male
3822	kk_KZ	Takhaui	male
3823	kk_KZ	Takhir	male
3824	kk_KZ	Takibai	male
3825	kk_KZ	Takim	male
3826	kk_KZ	Takyr	male
3827	kk_KZ	Talap	male
3828	kk_KZ	Talapbek	male
3829	kk_KZ	Talgar	male
3830	kk_KZ	Talgat	male
3831	kk_KZ	Talima	female
3832	kk_KZ	Talimgyz	female
3833	kk_KZ	Talina	female
3834	kk_KZ	Talip	male
3835	kk_KZ	Talipa	female
3836	kk_KZ	Talka	male
3837	kk_KZ	Talmas	male
3838	kk_KZ	Talshybyk	female
3839	kk_KZ	Talshyn	female
3840	kk_KZ	Tamabai	male
3841	kk_KZ	Tamara	female
3842	kk_KZ	Tamasha	female
3843	kk_KZ	Tamila	female
3844	kk_KZ	Tamina	female
3845	kk_KZ	Tana	female
3846	kk_KZ	Tanabai	male
3847	kk_KZ	Tanagul	female
3848	kk_KZ	Tanap	male
3849	kk_KZ	Tanapbai	male
3850	kk_KZ	Tanash	male
3851	kk_KZ	Tanat	male
3852	kk_KZ	Tanatar	male
3853	kk_KZ	Tanbol	male
3854	kk_KZ	Taneke	male
3855	kk_KZ	Tanirbai	male
3856	kk_KZ	Tanirbergen	male
3857	kk_KZ	Taniza	female
3858	kk_KZ	Tankar	male
3859	kk_KZ	Tansar	male
3860	kk_KZ	Tansholpan	female
3861	kk_KZ	Tansykbai	male
3862	kk_KZ	Tanzharyk	male
3863	kk_KZ	Tanzhas	male
3864	kk_KZ	Tanzila	female
3865	kk_KZ	Tanziya	female
3866	kk_KZ	Tapar	male
3867	kk_KZ	Taras	male
3868	kk_KZ	Tarbie	female
3869	kk_KZ	Targyn	male
3870	kk_KZ	Tasbala	female
3871	kk_KZ	Tasbolat	male
3872	kk_KZ	Tashen	male
3873	kk_KZ	Taskairat	male
3874	kk_KZ	Tasken	male
3875	kk_KZ	Taskyn	male
3876	kk_KZ	Taslima	female
3877	kk_KZ	Tasmagambet	male
3878	kk_KZ	Tasmukan	male
3879	kk_KZ	Tassai	male
3880	kk_KZ	Tassan	male
3881	kk_KZ	Tassanbai	male
3882	kk_KZ	Tassemen	male
3883	kk_KZ	Tassybek	male
3884	kk_KZ	Tassym	male
3885	kk_KZ	Tastai	male
3886	kk_KZ	Tastaibek	male
3887	kk_KZ	Tastan	male
3888	kk_KZ	Tastanbek	male
3889	kk_KZ	Tastemir	male
3890	kk_KZ	Tastulek	male
3891	kk_KZ	Taszhiger	male
3892	kk_KZ	Taten	male
3893	kk_KZ	Tatipa	female
3894	kk_KZ	Tatti	female
3895	kk_KZ	Tattibai	male
3896	kk_KZ	Tattibala	female
3897	kk_KZ	Tattigul	female
3898	kk_KZ	Tattigyz	female
3899	kk_KZ	Tattimbet	male
3900	kk_KZ	Tatubai	male
3901	kk_KZ	Tau	male
3902	kk_KZ	Tauan	male
3903	kk_KZ	Tauassat	male
3904	kk_KZ	Taubai	male
3905	kk_KZ	Tauekel	male
3906	kk_KZ	Taufikh	male
3907	kk_KZ	Tauir	male
3908	kk_KZ	Tauirbek	male
3909	kk_KZ	Tauke	male
3910	kk_KZ	Tauken	male
3911	kk_KZ	Taukesh	male
3912	kk_KZ	Tauman	male
3913	kk_KZ	Taushy	male
3914	kk_KZ	Tautan	male
3915	kk_KZ	Tauzhan	male
3916	kk_KZ	Tauzhat	male
3917	kk_KZ	Tazabek	male
3918	kk_KZ	Tazhi	male
3919	kk_KZ	Tazhibai	male
3920	kk_KZ	Tazhigul	female
3921	kk_KZ	Tazhikhan	female
3922	kk_KZ	Tazhimbet	male
3923	kk_KZ	Tegeran	male
3924	kk_KZ	Tegis	male
3925	kk_KZ	Telgozha	male
3926	kk_KZ	Telman	male
3927	kk_KZ	Telzhan	male
3928	kk_KZ	Temir	male
3929	kk_KZ	Temirali	male
3930	kk_KZ	Temirbai	male
3931	kk_KZ	Temirbek	male
3932	kk_KZ	Temirbolat	male
3933	kk_KZ	Temirgali	male
3934	kk_KZ	Temirkan	male
3935	kk_KZ	Temirkhan	male
3936	kk_KZ	Temirlan	male
3937	kk_KZ	Temirtas	male
3938	kk_KZ	Temirtulek	male
3939	kk_KZ	Tendik	female
3940	kk_KZ	Tenizbai	male
3941	kk_KZ	Ties	male
3942	kk_KZ	Tilebaldy	male
3943	kk_KZ	Tilegen	male
3944	kk_KZ	Tilek	male
3945	kk_KZ	Tilektes	male
3946	kk_KZ	Tilemis	male
3947	kk_KZ	Tilepbai	male
3948	kk_KZ	Tilepbergen	male
3949	kk_KZ	Tileubai	male
3950	kk_KZ	Tileuke	male
3951	kk_KZ	Tileukhan	male
3952	kk_KZ	Tileuli	male
3953	kk_KZ	Tileumurat	male
3954	kk_KZ	Tileuzhan	male
3955	kk_KZ	Tilmenbai	male
3956	kk_KZ	Timur	male
3957	kk_KZ	Tiyanak	male
3958	kk_KZ	Tobei	male
3959	kk_KZ	Toganas	male
3960	kk_KZ	Toguzak	male
3961	kk_KZ	Togysbai	male
3962	kk_KZ	Togyzak	male
3963	kk_KZ	Togyzbai	male
3964	kk_KZ	Togzhan	female
3965	kk_KZ	Togzhigit	male
3966	kk_KZ	Toibai	male
3967	kk_KZ	Toibala	female
3968	kk_KZ	Toibazar	male
3969	kk_KZ	Toibike	female
3970	kk_KZ	Toiboldy	male
3971	kk_KZ	Toigan	male
3972	kk_KZ	Toiganbai	male
3973	kk_KZ	Toiganbek	male
3974	kk_KZ	Toishy	male
3975	kk_KZ	Toka	male
3976	kk_KZ	Tokai	male
3977	kk_KZ	Tokan	male
3978	kk_KZ	Tokas	male
3979	kk_KZ	Tokatai	male
3980	kk_KZ	Tokbai	male
3981	kk_KZ	Tokbergen	male
3982	kk_KZ	Token	male
3983	kk_KZ	Tokmagambet	male
3984	kk_KZ	Tokmukambet	male
3985	kk_KZ	Tokmyrza	male
3986	kk_KZ	Tokpan	male
3987	kk_KZ	Toksaba	male
3988	kk_KZ	Toksan	male
3989	kk_KZ	Toksanbai	male
3990	kk_KZ	Toksulu	female
3991	kk_KZ	Toktagali	male
3992	kk_KZ	Toktagan	male
3993	kk_KZ	Toktamys	male
3994	kk_KZ	Toktar	male
3995	kk_KZ	Toktarbai	male
3996	kk_KZ	Toktargali	male
3997	kk_KZ	Toktarkan	male
3998	kk_KZ	Toktassyn	male
3999	kk_KZ	Toktybai	male
4000	kk_KZ	Tokyr	male
4001	kk_KZ	Tolagai	male
4002	kk_KZ	Tolai	male
4003	kk_KZ	Tolbai	male
4004	kk_KZ	Tolebai	male
4005	kk_KZ	Tolegen	male
4006	kk_KZ	Tolek	male
4007	kk_KZ	Tolekei	male
4008	kk_KZ	Tolepkali	male
4009	kk_KZ	Tolganai	female
4010	kk_KZ	Tolgozha	male
4011	kk_KZ	Tolkyn	female
4012	kk_KZ	Tolman	male
4013	kk_KZ	Toltan	male
4014	kk_KZ	Tolybai	male
4015	kk_KZ	Tolybek	male
4016	kk_KZ	Tolymbet	male
4017	kk_KZ	Tolys	male
4018	kk_KZ	Tolysbala	female
4019	kk_KZ	Tolysh	female
4020	kk_KZ	Tolzhan	male
4021	kk_KZ	Toman	male
4022	kk_KZ	Torebai	male
4023	kk_KZ	Torebek	male
4024	kk_KZ	Toregeldi	male
4025	kk_KZ	Torekhan	male
4026	kk_KZ	Torezhan	male
4027	kk_KZ	Torgai	male
4028	kk_KZ	Torgyn	female
4029	kk_KZ	Torlambai	male
4030	kk_KZ	Torpak	male
4031	kk_KZ	Torsan	male
4032	kk_KZ	Tortai	male
4033	kk_KZ	Torymbala	female
4034	kk_KZ	Torymzhan	female
4035	kk_KZ	Torzhan	female
4036	kk_KZ	Totai	male
4037	kk_KZ	Totiya	female
4038	kk_KZ	Toty	female
4039	kk_KZ	Totygus	female
4040	kk_KZ	Toyash	female
4041	kk_KZ	Tubek	male
4042	kk_KZ	Tuganbai	male
4043	kk_KZ	Tugelbai	male
4044	kk_KZ	Tuimekhan	female
4045	kk_KZ	Tulek	male
4046	kk_KZ	Tulkibai	male
4047	kk_KZ	Tulymkhan	female
4048	kk_KZ	Tumarbai	male
4049	kk_KZ	Tumarbek	male
4050	kk_KZ	Tumarsha	female
4051	kk_KZ	Tumarzhan	male
4052	kk_KZ	Tumen	male
4053	kk_KZ	Tumenbai	male
4054	kk_KZ	Tungatar	male
4055	kk_KZ	Tungyshbai	male
4056	kk_KZ	Turabai	male
4057	kk_KZ	Turakhan	female
4058	kk_KZ	Turap	male
4059	kk_KZ	Turapbai	male
4060	kk_KZ	Turash	male
4061	kk_KZ	Turashyl	male
4062	kk_KZ	Turatai	female
4063	kk_KZ	Turbek	male
4064	kk_KZ	Turdaly	male
4065	kk_KZ	Turdybek	male
4066	kk_KZ	Turgan	female
4067	kk_KZ	Turganai	female
4068	kk_KZ	Turganbek	male
4069	kk_KZ	Turgangul	female
4070	kk_KZ	Turgat	male
4071	kk_KZ	Turgenbai	male
4072	kk_KZ	Turgyn	male
4073	kk_KZ	Turgynbai	male
4074	kk_KZ	Turgynbek	male
4075	kk_KZ	Turke	male
4076	kk_KZ	Turkesh	male
4077	kk_KZ	Turlybai	male
4078	kk_KZ	Turmagambet	male
4079	kk_KZ	Turmanzhan	male
4080	kk_KZ	Tursyn	male
4081	kk_KZ	Tursynai	female
4082	kk_KZ	Tursynbai	male
4083	kk_KZ	Tursynbek	male
4084	kk_KZ	Tursyngul	female
4085	kk_KZ	Tursynkhan	female
4086	kk_KZ	Tursynzhan	male
4087	kk_KZ	Turymkhan	female
4088	kk_KZ	Turymtai	male
4089	kk_KZ	Turys	male
4090	kk_KZ	Turysbek	male
4091	kk_KZ	Tussen	male
4092	kk_KZ	Tussip	male
4093	kk_KZ	Tussipzhan	male
4094	kk_KZ	Tuyak	male
4095	kk_KZ	Tuyakbai	male
4096	kk_KZ	Tyiyshbek	male
4097	kk_KZ	Tynaly	male
4098	kk_KZ	Tynybai	male
4099	kk_KZ	Tynybek	male
4100	kk_KZ	Tynym	male
4101	kk_KZ	Tynymbai	male
4102	kk_KZ	Tynys	male
4103	kk_KZ	Tynysbai	male
4104	kk_KZ	Tynyshgul	female
4105	kk_KZ	Tynyshtygul	male
4106	kk_KZ	Tynyshtyk	male
4107	kk_KZ	Tynyshtykbek	male
4108	kk_KZ	Tynystan	male
4109	kk_KZ	Uaida	male
4110	kk_KZ	Uaikan	male
4111	kk_KZ	Uaiys	male
4112	kk_KZ	Uakap	male
4113	kk_KZ	Uakhap	male
4114	kk_KZ	Uakhat	male
4115	kk_KZ	Uakhit	male
4116	kk_KZ	Uali	male
4117	kk_KZ	Ualiakhmet	male
4118	kk_KZ	Ualit	male
4119	kk_KZ	Uanbai	male
4120	kk_KZ	Uandyk	male
4121	kk_KZ	Uassila	female
4122	kk_KZ	Uassima	female
4123	kk_KZ	Uatai	male
4124	kk_KZ	Uazipa	female
4125	kk_KZ	Ubaida	female
4126	kk_KZ	Ubbi	male
4127	kk_KZ	Ubiyana	female
4128	kk_KZ	Uderbai	male
4129	kk_KZ	Uderi	male
4130	kk_KZ	Ufa	male
4131	kk_KZ	Uiykbai	male
4132	kk_KZ	Uki	male
4133	kk_KZ	Ulan	male
4134	kk_KZ	Ulas	male
4135	kk_KZ	Ulbala	female
4136	kk_KZ	Ulbibi	female
4137	kk_KZ	Ulbike	female
4138	kk_KZ	Ulda	female
4139	kk_KZ	Uldai	female
4140	kk_KZ	Uldan	female
4141	kk_KZ	Uldysh	female
4142	kk_KZ	Ulfat	female
4143	kk_KZ	Ulgai	male
4144	kk_KZ	Ulganai	female
4145	kk_KZ	Ulgibai	male
4146	kk_KZ	Ulkhan	female
4147	kk_KZ	Ulmakan	male
4148	kk_KZ	Ulpa	female
4149	kk_KZ	Ulpan	female
4150	kk_KZ	Ulpanai	female
4151	kk_KZ	Ulshym	female
4152	kk_KZ	Ultybai	male
4153	kk_KZ	Ulyk	male
4154	kk_KZ	Ulykbek	male
4155	kk_KZ	Ulymbet	male
4156	kk_KZ	Ulzhan	female
4157	kk_KZ	Umbet	male
4158	kk_KZ	Umbetali	male
4159	kk_KZ	Umbetbai	male
4160	kk_KZ	Umbetzhan	male
4161	kk_KZ	Umigulsim	female
4162	kk_KZ	Umitai	female
4163	kk_KZ	Umitan	female
4164	kk_KZ	Umitbai	male
4165	kk_KZ	Umitzhan	female
4166	kk_KZ	Umsyn	female
4167	kk_KZ	Umsynai	female
4168	kk_KZ	Umsyndyk	female
4169	kk_KZ	Urgenishbai	male
4170	kk_KZ	Urimbai	male
4171	kk_KZ	Urimkan	male
4172	kk_KZ	Urimzhan	male
4173	kk_KZ	Uripan	female
4174	kk_KZ	Uriya	female
4175	kk_KZ	Urkiya	female
4176	kk_KZ	Urtai	male
4177	kk_KZ	Urzada	female
4178	kk_KZ	Urzhapiya	female
4179	kk_KZ	Urziya	female
4180	kk_KZ	Ussa	male
4181	kk_KZ	Ussabai	male
4182	kk_KZ	Ussabek	male
4183	kk_KZ	Ussebai	male
4184	kk_KZ	Ussen	male
4185	kk_KZ	Ussenbai	male
4186	kk_KZ	Ussenbek	male
4187	kk_KZ	Ussengali	male
4188	kk_KZ	Ussipbek	male
4189	kk_KZ	Ustem	male
4190	kk_KZ	Uykbai	male
4191	kk_KZ	Uzak	male
4192	kk_KZ	Uzakbai	male
4193	kk_KZ	Valentina	female
4194	kk_KZ	Venera	female
4195	kk_KZ	Vera	female
4196	kk_KZ	Vilora	female
4197	kk_KZ	Vlada	female
4198	kk_KZ	Ybyrai	male
4199	kk_KZ	Ybyraiym	male
4200	kk_KZ	Ybyrash	male
4201	kk_KZ	Ydyrys	male
4202	kk_KZ	Yedige	male
4203	kk_KZ	Yedigen	male
4204	kk_KZ	Yedil	male
4205	kk_KZ	Yedilbai	male
4206	kk_KZ	Yegei	male
4207	kk_KZ	Yegemberdi	male
4208	kk_KZ	Yegeubai	male
4209	kk_KZ	Yegibai	male
4210	kk_KZ	Yegizbai	male
4211	kk_KZ	Yegizbek	male
4212	kk_KZ	Yegizek	male
4213	kk_KZ	Yelaman	male
4214	kk_KZ	Yelbar	male
4215	kk_KZ	Yelbas	male
4216	kk_KZ	Yelbastar	male
4217	kk_KZ	Yelbek	male
4218	kk_KZ	Yeldana	female
4219	kk_KZ	Yeldar	male
4220	kk_KZ	Yeldes	male
4221	kk_KZ	Yeldos	male
4222	kk_KZ	Yelebai	male
4223	kk_KZ	Yelebek	male
4224	kk_KZ	Yelen	male
4225	kk_KZ	Yelena	female
4226	kk_KZ	Yelentai	female
4227	kk_KZ	Yeles	male
4228	kk_KZ	Yelesh	male
4229	kk_KZ	Yeleu	male
4230	kk_KZ	Yeleubai	male
4231	kk_KZ	Yeleuis	male
4232	kk_KZ	Yeleuken	male
4233	kk_KZ	Yelgul	female
4234	kk_KZ	Yelibai	male
4235	kk_KZ	Yelibek	male
4236	kk_KZ	Yelkam	male
4237	kk_KZ	Yelkon	male
4238	kk_KZ	Yelkondy	male
4239	kk_KZ	Yelman	male
4240	kk_KZ	Yelmukambek	male
4241	kk_KZ	Yelmurat	male
4242	kk_KZ	Yelmyrza	male
4243	kk_KZ	Yelnar	male
4244	kk_KZ	Yelnaz	male
4245	kk_KZ	Yelnazar	male
4246	kk_KZ	Yelnur	male
4247	kk_KZ	Yelshibai	male
4248	kk_KZ	Yelsuier	male
4249	kk_KZ	Yeltan	male
4250	kk_KZ	Yeltok	male
4251	kk_KZ	Yelubai	male
4252	kk_KZ	Yelzhan	male
4253	kk_KZ	Yelzhar	male
4254	kk_KZ	Yelzhas	male
4255	kk_KZ	Yelzhassar	male
4256	kk_KZ	Yemelzhan	male
4257	kk_KZ	Yemenaly	male
4258	kk_KZ	Yemil	male
4259	kk_KZ	Yenlik	female
4260	kk_KZ	Yensebek	male
4261	kk_KZ	Yensegen	male
4262	kk_KZ	Yensep	male
4263	kk_KZ	Yenser	male
4264	kk_KZ	Yeraly	male
4265	kk_KZ	Yerassyl	male
4266	kk_KZ	Yerbai	male
4267	kk_KZ	Yerbak	male
4268	kk_KZ	Yerbala	male
4269	kk_KZ	Yerbatyr	male
4270	kk_KZ	Yerbek	male
4271	kk_KZ	Yerbel	male
4272	kk_KZ	Yerbol	male
4273	kk_KZ	Yerbolat	male
4274	kk_KZ	Yerbolsyn	male
4275	kk_KZ	Yerbossyn	male
4276	kk_KZ	Yerbota	male
4277	kk_KZ	Yerdana	male
4278	kk_KZ	Yerdar	male
4279	kk_KZ	Yerdaulet	male
4280	kk_KZ	Yerden	male
4281	kk_KZ	Yerdenai	male
4282	kk_KZ	Yerdenbai	male
4283	kk_KZ	Yerdenbek	male
4284	kk_KZ	Yerdesh	male
4285	kk_KZ	Yeren	male
4286	kk_KZ	Yerezhep	male
4287	kk_KZ	Yergalau	male
4288	kk_KZ	Yergali	male
4289	kk_KZ	Yergara	male
4290	kk_KZ	Yergazy	male
4291	kk_KZ	Yergesh	male
4292	kk_KZ	Yergozha	male
4293	kk_KZ	Yerik	male
4294	kk_KZ	Yerikti	male
4295	kk_KZ	Yerimbek	male
4296	kk_KZ	Yerimbet	male
4297	kk_KZ	Yerke	female
4298	kk_KZ	Yerkebai	male
4299	kk_KZ	Yerkebala	female
4300	kk_KZ	Yerkebolat	male
4301	kk_KZ	Yerkebulan	male
4302	kk_KZ	Yerkegali	male
4303	kk_KZ	Yerkegul	female
4304	kk_KZ	Yerkesh	male
4305	kk_KZ	Yerketai	male
4306	kk_KZ	Yerkezhan	female
4307	kk_KZ	Yerkin	male
4308	kk_KZ	Yerkinbai	male
4309	kk_KZ	Yerkinbek	male
4310	kk_KZ	Yerkingali	male
4311	kk_KZ	Yerkinkul	female
4312	kk_KZ	Yerkintai	male
4313	kk_KZ	Yerkish	female
4314	kk_KZ	Yerkuat	male
4316	kk_KZ	Yerlen	male
4317	kk_KZ	Yerlepes	male
4318	kk_KZ	Yerles	male
4319	kk_KZ	Yerlik	male
4320	kk_KZ	Yermagambet	male
4321	kk_KZ	Yerman	male
4322	kk_KZ	Yermat	male
4323	kk_KZ	Yermek	male
4324	kk_KZ	Yermekali	male
4325	kk_KZ	Yermekkali	male
4326	kk_KZ	Yermukambet	male
4327	kk_KZ	Yermurat	male
4328	kk_KZ	Yernar	male
4329	kk_KZ	Yernazar	male
4330	kk_KZ	Yernur	male
4331	kk_KZ	Yersaga	male
4332	kk_KZ	Yersaiyn	male
4333	kk_KZ	Yersali	male
4334	kk_KZ	Yersary	male
4335	kk_KZ	Yerseiit	male
4336	kk_KZ	Yershu	male
4337	kk_KZ	Yersultan	male
4338	kk_KZ	Yertai	male
4339	kk_KZ	Yertiles	male
4340	kk_KZ	Yertileu	male
4341	kk_KZ	Yertis	male
4342	kk_KZ	Yertugan	male
4343	kk_KZ	Yerubai	male
4344	kk_KZ	Yerzada	female
4345	kk_KZ	Yerzhan	male
4346	kk_KZ	Yerzhekei	male
4347	kk_KZ	Yerzhigit	male
4348	kk_KZ	Yerzhuman	male
4349	kk_KZ	Yerziba	female
4350	kk_KZ	Yerziya	female
4351	kk_KZ	Yerziyash	female
4352	kk_KZ	Yes	male
4353	kk_KZ	Yesbai	male
4354	kk_KZ	Yesbatyr	male
4355	kk_KZ	Yesberdi	male
4356	kk_KZ	Yesbergen	male
4357	kk_KZ	Yesbol	male
4358	kk_KZ	Yesbolat	male
4359	kk_KZ	Yesdauir	male
4360	kk_KZ	Yesdaulet	male
4361	kk_KZ	Yeshaman	male
4362	kk_KZ	Yeshbai	male
4363	kk_KZ	Yeshken	male
4364	kk_KZ	Yeshmukhambet	male
4365	kk_KZ	Yeshmurat	male
4366	kk_KZ	Yeshtai	male
4367	kk_KZ	Yeskaiyr	male
4368	kk_KZ	Yeskali	male
4369	kk_KZ	Yesken	male
4370	kk_KZ	Yeskendir	male
4371	kk_KZ	Yeskozha	male
4372	kk_KZ	Yesmagambet	male
4373	kk_KZ	Yesman	male
4374	kk_KZ	Yesmukan	male
4375	kk_KZ	Yesmurat	male
4376	kk_KZ	Yesnazar	male
4377	kk_KZ	Yespembet	male
4378	kk_KZ	Yessali	male
4379	kk_KZ	Yessei	male
4380	kk_KZ	Yesseizhan	male
4381	kk_KZ	Yessen	male
4382	kk_KZ	Yessenai	male
4383	kk_KZ	Yessenali	male
4384	kk_KZ	Yessenaly	male
4385	kk_KZ	Yessenaman	male
4386	kk_KZ	Yessenbai	male
4387	kk_KZ	Yessenbaky	male
4388	kk_KZ	Yessenberdi	male
4389	kk_KZ	Yessendik	male
4390	kk_KZ	Yessengali	male
4391	kk_KZ	Yessengul	male
4392	kk_KZ	Yessenkan	male
4393	kk_KZ	Yessenmurat	male
4394	kk_KZ	Yessenseiit	male
4395	kk_KZ	Yessentai	male
4396	kk_KZ	Yessentemir	male
4397	kk_KZ	Yessenzhan	male
4398	kk_KZ	Yessenzhol	male
4399	kk_KZ	Yesset	male
4400	kk_KZ	Yessil	male
4401	kk_KZ	Yessilbai	male
4402	kk_KZ	Yessim	male
4403	kk_KZ	Yessimbek	male
4404	kk_KZ	Yessimkhan	male
4405	kk_KZ	Yessimzhan	male
4406	kk_KZ	Yessirke	male
4407	kk_KZ	Yessirkegen	male
4408	kk_KZ	Yessirkep	male
4409	kk_KZ	Yestemes	male
4410	kk_KZ	Yesten	male
4411	kk_KZ	Yestibai	male
4412	kk_KZ	Yeszhan	male
4413	kk_KZ	Yksan	male
4414	kk_KZ	Ykylas	male
4415	kk_KZ	Yntybai	male
4416	kk_KZ	Yntyk	male
4417	kk_KZ	Yntykbai	male
4418	kk_KZ	Yntymak	male
4419	kk_KZ	Yntyzar	male
4420	kk_KZ	Yrym	male
4421	kk_KZ	Yrymbai	male
4422	kk_KZ	Yrymbek	male
4423	kk_KZ	Yrymet	male
4424	kk_KZ	Yrymkul	male
4425	kk_KZ	Yrys	male
4426	kk_KZ	Yrysbai	male
4427	kk_KZ	Yrysbala	female
4428	kk_KZ	Yrysbek	male
4429	kk_KZ	Yrysbergen	male
4430	kk_KZ	Yryskeldi	male
4431	kk_KZ	Yryskhan	female
4432	kk_KZ	Yryssaldy	male
4433	kk_KZ	Yrysty	female
4434	kk_KZ	Yryszhan	male
4435	kk_KZ	Yrzabai	male
4436	kk_KZ	Yrzabek	male
4437	kk_KZ	Yskak	male
4438	kk_KZ	Yskakbai	male
4439	kk_KZ	Ysmagul	male
4440	kk_KZ	Ysmaiyl	male
4441	kk_KZ	Ysmakan	male
4442	kk_KZ	Ysmat	male
4443	kk_KZ	Ysmatbek	male
4444	kk_KZ	Yspan	male
4445	kk_KZ	Yspandiyar	male
4446	kk_KZ	Ystambaky	male
4447	kk_KZ	Zabi	male
4448	kk_KZ	Zabila	female
4449	kk_KZ	Zabira	female
4450	kk_KZ	Zagida	female
4451	kk_KZ	Zagila	female
4452	kk_KZ	Zagipa	female
4453	kk_KZ	Zagira	female
4454	kk_KZ	Zagisha	female
4455	kk_KZ	Zaida	female
4456	kk_KZ	Zaina	female
4457	kk_KZ	Zaira	female
4458	kk_KZ	Zaisa	female
4459	kk_KZ	Zait	male
4460	kk_KZ	Zaituna	female
4461	kk_KZ	Zaiyr	male
4462	kk_KZ	Zaiyrbek	male
4463	kk_KZ	Zakan	male
4464	kk_KZ	Zakariya	male
4465	kk_KZ	Zakaryan	male
4466	kk_KZ	Zakash	male
4467	kk_KZ	Zaki	male
4468	kk_KZ	Zakina	female
4469	kk_KZ	Zakir	male
4470	kk_KZ	Zakira	female
4471	kk_KZ	Zakirbai	male
4472	kk_KZ	Zakiya	female
4473	kk_KZ	Zakoniya	female
4474	kk_KZ	Zakumbai	male
4475	kk_KZ	Zaman	male
4476	kk_KZ	Zamanbek	male
4477	kk_KZ	Zamaniya	female
4478	kk_KZ	Zamiliya	female
4479	kk_KZ	Zamir	male
4480	kk_KZ	Zamira	female
4481	kk_KZ	Zamza	female
4482	kk_KZ	Zamzagul	female
4483	kk_KZ	Zamzamiya	female
4484	kk_KZ	Zamzegul	female
4485	kk_KZ	Zamziya	female
4486	kk_KZ	Zangar	male
4487	kk_KZ	Zara	female
4488	kk_KZ	Zarema	female
4489	kk_KZ	Zariga	female
4490	kk_KZ	Zarina	female
4491	kk_KZ	Zaripa	female
4492	kk_KZ	Zaripkan	male
4493	kk_KZ	Zarisha	female
4494	kk_KZ	Zarlyk	female
4495	kk_KZ	Zarya	female
4496	kk_KZ	Zauir	male
4497	kk_KZ	Zauirbai	male
4498	kk_KZ	Zaure	female
4499	kk_KZ	Zauresh	female
4500	kk_KZ	Zauza	female
4501	kk_KZ	Zeine	female
4502	kk_KZ	Zeinegul	female
4503	kk_KZ	Zeinekhan	female
4504	kk_KZ	Zeinel	male
4505	kk_KZ	Zeinep	female
4506	kk_KZ	Zeinesh	female
4507	kk_KZ	Zeinet	male
4508	kk_KZ	Zeinolla	male
4509	kk_KZ	Zeinur	male
4510	kk_KZ	Zeitik	male
4511	kk_KZ	Zeken	male
4512	kk_KZ	Zemfira	female
4513	kk_KZ	Zerde	female
4514	kk_KZ	Zere	female
4515	kk_KZ	Zergerbek	male
4516	kk_KZ	Zergul	female
4517	kk_KZ	Zhabai	male
4518	kk_KZ	Zhabak	male
4519	kk_KZ	Zhabal	male
4520	kk_KZ	Zhaban	male
4521	kk_KZ	Zhabas	male
4522	kk_KZ	Zhabatai	male
4523	kk_KZ	Zhabi	male
4524	kk_KZ	Zhabyrbai	male
4525	kk_KZ	Zhadai	male
4526	kk_KZ	Zhadan	male
4527	kk_KZ	Zhadiger	male
4528	kk_KZ	Zhagan	male
4529	kk_KZ	Zhagatai	male
4530	kk_KZ	Zhagypar	male
4531	kk_KZ	Zhaidar	male
4532	kk_KZ	Zhaidarbek	male
4533	kk_KZ	Zhaikak	male
4534	kk_KZ	Zhaiken	male
4535	kk_KZ	Zhailau	male
4536	kk_KZ	Zhailaubai	male
4537	kk_KZ	Zhailybai	male
4538	kk_KZ	Zhaina	female
4539	kk_KZ	Zhainak	male
4540	kk_KZ	Zhainakan	female
4541	kk_KZ	Zhaisak	male
4542	kk_KZ	Zhaisan	male
4543	kk_KZ	Zhaisanbai	male
4544	kk_KZ	Zhaisanbek	male
4545	kk_KZ	Zhaitabar	male
4546	kk_KZ	Zhaiyk	male
4547	kk_KZ	Zhaka	male
4548	kk_KZ	Zhakai	male
4549	kk_KZ	Zhakan	male
4550	kk_KZ	Zhakash	male
4551	kk_KZ	Zhakat	male
4552	kk_KZ	Zhakatai	male
4553	kk_KZ	Zhakau	male
4554	kk_KZ	Zhaken	male
4555	kk_KZ	Zhaket	male
4556	kk_KZ	Zhaki	male
4557	kk_KZ	Zhakiya	male
4558	kk_KZ	Zhaksybai	male
4559	kk_KZ	Zhaksygali	male
4560	kk_KZ	Zhaksygul	male
4561	kk_KZ	Zhaksylyk	male
4562	kk_KZ	Zhaksymurat	male
4563	kk_KZ	Zhakyn	male
4564	kk_KZ	Zhakynbek	male
4565	kk_KZ	Zhakyp	male
4566	kk_KZ	Zhakypbai	male
4567	kk_KZ	Zhakypbek	male
4568	kk_KZ	Zhalbyr	male
4569	kk_KZ	Zhalel	male
4570	kk_KZ	Zhalgas	male
4571	kk_KZ	Zhalgasbai	male
4572	kk_KZ	Zhalgasbek	male
4573	kk_KZ	Zhalila	female
4574	kk_KZ	Zhalmukan	male
4575	kk_KZ	Zhaltyr	male
4576	kk_KZ	Zhalyn	male
4577	kk_KZ	Zhalynsha	female
4578	kk_KZ	Zhamadi	male
4579	kk_KZ	Zhamal	female
4580	kk_KZ	Zhamalai	female
4581	kk_KZ	Zhamalbek	male
4582	kk_KZ	Zhamali	female
4583	kk_KZ	Zhamaliya	female
4584	kk_KZ	Zhamalkhan	female
4585	kk_KZ	Zhamangara	male
4586	kk_KZ	Zhambai	male
4587	kk_KZ	Zhamby	female
4588	kk_KZ	Zhambyl	male
4589	kk_KZ	Zhamen	male
4590	kk_KZ	Zhami	male
4591	kk_KZ	Zhamiga	female
4592	kk_KZ	Zhamil	male
4593	kk_KZ	Zhamila	female
4594	kk_KZ	Zhamish	male
4595	kk_KZ	Zhamshit	male
4596	kk_KZ	Zhamykai	male
4597	kk_KZ	Zhamykhan	male
4598	kk_KZ	Zhanabai	male
4599	kk_KZ	Zhanabek	male
4600	kk_KZ	Zhanabil	male
4601	kk_KZ	Zhanai	male
4602	kk_KZ	Zhanaidar	male
4603	kk_KZ	Zhanak	male
4604	kk_KZ	Zhanakhmet	male
4605	kk_KZ	Zhanaly	male
4606	kk_KZ	Zhanan	female
4607	kk_KZ	Zhanana	female
4608	kk_KZ	Zhanargul	female
4609	kk_KZ	Zhanarys	male
4610	kk_KZ	Zhanarystan	male
4611	kk_KZ	Zhanas	male
4612	kk_KZ	Zhanatai	male
4613	kk_KZ	Zhanatbek	male
4614	kk_KZ	Zhanatkul	female
4615	kk_KZ	Zhanaziya	female
4616	kk_KZ	Zhanbai	male
4617	kk_KZ	Zhanbaki	male
4618	kk_KZ	Zhanbek	male
4619	kk_KZ	Zhanbike	female
4620	kk_KZ	Zhanbolat	male
4621	kk_KZ	Zhanbossyn	male
4622	kk_KZ	Zhanbota	male
4623	kk_KZ	Zhanbura	male
4624	kk_KZ	Zhandabol	male
4625	kk_KZ	Zhandai	male
4626	kk_KZ	Zhandar	male
4627	kk_KZ	Zhandarbek	male
4628	kk_KZ	Zhanderke	male
4629	kk_KZ	Zhandos	male
4630	kk_KZ	Zhandybai	male
4631	kk_KZ	Zhanerke	female
4632	kk_KZ	Zhanerkin	male
4633	kk_KZ	Zhanetta	female
4634	kk_KZ	Zhangali	male
4635	kk_KZ	Zhangazy	male
4636	kk_KZ	Zhangeldi	male
4637	kk_KZ	Zhangir	male
4638	kk_KZ	Zhangoilyk	male
4639	kk_KZ	Zhangozy	male
4640	kk_KZ	Zhani	male
4641	kk_KZ	Zhanibek	male
4642	kk_KZ	Zhanifa	female
4643	kk_KZ	Zhaniga	female
4644	kk_KZ	Zhanipa	female
4645	kk_KZ	Zhanira	female
4646	kk_KZ	Zhaniya	female
4647	kk_KZ	Zhankabi	male
4648	kk_KZ	Zhanke	male
4649	kk_KZ	Zhankuat	male
4650	kk_KZ	Zhankumis	female
4651	kk_KZ	Zhanmurat	male
4652	kk_KZ	Zhanna	female
4653	kk_KZ	Zhannat	female
4654	kk_KZ	Zhannazar	male
4655	kk_KZ	Zhanniyaz	male
4656	kk_KZ	Zhanoraz	male
4657	kk_KZ	Zhanpeiis	male
4658	kk_KZ	Zhansal	male
4659	kk_KZ	Zhansary	male
4660	kk_KZ	Zhanshuak	male
4661	kk_KZ	Zhansugir	male
4662	kk_KZ	Zhansuier	male
4663	kk_KZ	Zhansultan	male
4664	kk_KZ	Zhantai	male
4665	kk_KZ	Zhantaimas	male
4666	kk_KZ	Zhantas	male
4667	kk_KZ	Zhantau	male
4668	kk_KZ	Zhanteke	male
4669	kk_KZ	Zhantemir	male
4670	kk_KZ	Zhantileu	male
4671	kk_KZ	Zhantirek	male
4672	kk_KZ	Zhantore	male
4673	kk_KZ	Zhantuar	male
4674	kk_KZ	Zhantugan	male
4675	kk_KZ	Zhantur	male
4676	kk_KZ	Zhantursyn	male
4677	kk_KZ	Zhanuzak	male
4678	kk_KZ	Zhanzha	male
4679	kk_KZ	Zhanzhigit	male
4680	kk_KZ	Zhanzila	female
4681	kk_KZ	Zhanziya	female
4682	kk_KZ	Zhapak	male
4683	kk_KZ	Zhapan	male
4684	kk_KZ	Zhapar	male
4685	kk_KZ	Zhappar	male
4686	kk_KZ	Zhappas	male
4687	kk_KZ	Zhappasbai	male
4688	kk_KZ	Zharas	male
4689	kk_KZ	Zharbas	male
4690	kk_KZ	Zharbol	male
4691	kk_KZ	Zharbossyn	male
4692	kk_KZ	Zhardem	male
4693	kk_KZ	Zharkesh	male
4694	kk_KZ	Zharkyn	male
4695	kk_KZ	Zharkynbeis	male
4696	kk_KZ	Zharmak	male
4697	kk_KZ	Zhartybai	male
4698	kk_KZ	Zharyk	male
4699	kk_KZ	Zharykbai	male
4700	kk_KZ	Zharyketer	male
4701	kk_KZ	Zharylgap	male
4702	kk_KZ	Zharylkassyn	male
4703	kk_KZ	Zharymbet	male
4704	kk_KZ	Zhasbilim	male
4705	kk_KZ	Zhaskairat	male
4706	kk_KZ	Zhaskelen	male
4707	kk_KZ	Zhasken	male
4708	kk_KZ	Zhassakbai	male
4709	kk_KZ	Zhassamys	male
4710	kk_KZ	Zhassulan	male
4711	kk_KZ	Zhassura	female
4712	kk_KZ	Zhassuzak	male
4713	kk_KZ	Zhassybai	male
4714	kk_KZ	Zhastalap	male
4715	kk_KZ	Zhatai	male
4716	kk_KZ	Zhauar	male
4717	kk_KZ	Zhauger	male
4718	kk_KZ	Zhaukhar	female
4719	kk_KZ	Zhaukhariya	female
4720	kk_KZ	Zhautik	male
4721	kk_KZ	Zhaydaulet	male
4722	kk_KZ	Zhazira	female
4723	kk_KZ	Zhazken	male
4724	kk_KZ	Zhazybai	male
4725	kk_KZ	Zhazyk	male
4726	kk_KZ	Zhazylbek	male
4727	kk_KZ	Zheken	male
4728	kk_KZ	Zheksen	male
4729	kk_KZ	Zheksenbai	male
4730	kk_KZ	Zhemisbek	male
4731	kk_KZ	Zhemisgul	female
4732	kk_KZ	Zhemissai	female
4733	kk_KZ	Zhenis	male
4734	kk_KZ	Zhenisgul	female
4735	kk_KZ	Zheniskan	male
4736	kk_KZ	Zhetekesh	male
4737	kk_KZ	Zheten	male
4738	kk_KZ	Zhetes	male
4739	kk_KZ	Zhetibai	male
4740	kk_KZ	Zhetigen	male
4741	kk_KZ	Zhetik	male
4742	kk_KZ	Zhetistik	male
4743	kk_KZ	Zhetkergen	male
4744	kk_KZ	Zhetkinshek	male
4745	kk_KZ	Zhetkiz	male
4746	kk_KZ	Zhibek	female
4747	kk_KZ	Zhidebai	male
4748	kk_KZ	Zhienbai	male
4749	kk_KZ	Zhienbek	male
4750	kk_KZ	Zhiengali	male
4751	kk_KZ	Zhiger	male
4752	kk_KZ	Zhikhansha	male
4753	kk_KZ	Zhirenshe	male
4754	kk_KZ	Zhiyas	male
4755	kk_KZ	Zhiynysbai	male
4756	kk_KZ	Zholai	male
4757	kk_KZ	Zholan	male
4758	kk_KZ	Zholbai	male
4759	kk_KZ	Zholdas	male
4760	kk_KZ	Zholdasbai	male
4761	kk_KZ	Zholdasbek	male
4762	kk_KZ	Zholdaskan	male
4763	kk_KZ	Zholdy	male
4764	kk_KZ	Zholdybai	male
4765	kk_KZ	Zholmukamet	male
4766	kk_KZ	Zholmurat	male
4767	kk_KZ	Zholmyrza	male
4768	kk_KZ	Zholseiit	male
4769	kk_KZ	Zholshybek	male
4770	kk_KZ	Zholtai	male
4771	kk_KZ	Zholymbet	male
4772	kk_KZ	Zhomart	male
4773	kk_KZ	Zhomartbai	male
4774	kk_KZ	Zhomartbek	male
4775	kk_KZ	Zhora	male
4776	kk_KZ	Zhorabai	male
4777	kk_KZ	Zhorabek	male
4778	kk_KZ	Zhordan	male
4779	kk_KZ	Zhossanbai	male
4780	kk_KZ	Zhotabai	male
4781	kk_KZ	Zhuandyk	male
4782	kk_KZ	Zhuanysh	male
4783	kk_KZ	Zhuanyshbai	male
4784	kk_KZ	Zhubaida	female
4785	kk_KZ	Zhuban	male
4786	kk_KZ	Zhubaniyaz	male
4787	kk_KZ	Zhubanysh	male
4788	kk_KZ	Zhugirali	male
4789	kk_KZ	Zhuldyz	female
4790	kk_KZ	Zhuldyzai	female
4791	kk_KZ	Zhuma	male
4792	kk_KZ	Zhumabai	male
4793	kk_KZ	Zhumabek	male
4794	kk_KZ	Zhumabike	female
4795	kk_KZ	Zhumadil	male
4796	kk_KZ	Zhumadila	female
4797	kk_KZ	Zhumagali	male
4798	kk_KZ	Zhumagazy	male
4799	kk_KZ	Zhumageldi	male
4800	kk_KZ	Zhumagyz	female
4801	kk_KZ	Zhumakhan	male
4802	kk_KZ	Zhumakhmet	male
4803	kk_KZ	Zhumali	male
4804	kk_KZ	Zhumamurat	male
4805	kk_KZ	Zhuman	male
4806	kk_KZ	Zhumanazar	male
4807	kk_KZ	Zhumanbai	male
4808	kk_KZ	Zhumaniyaz	male
4809	kk_KZ	Zhumat	male
4810	kk_KZ	Zhumatai	male
4811	kk_KZ	Zhumaziya	female
4812	kk_KZ	Zhumyr	male
4813	kk_KZ	Zhunis	male
4814	kk_KZ	Zhunisbai	male
4815	kk_KZ	Zhupar	female
4816	kk_KZ	Zhures	male
4817	kk_KZ	Zhurgen	male
4818	kk_KZ	Zhursin	male
4819	kk_KZ	Zhurtbai	male
4820	kk_KZ	Zhurtybai	male
4821	kk_KZ	Zhussanbai	male
4822	kk_KZ	Zhussibali	male
4823	kk_KZ	Zhussip	male
4824	kk_KZ	Zhussipbek	male
4825	kk_KZ	Zhussipkali	male
4826	kk_KZ	Zhuzai	male
4827	kk_KZ	Zhuzbai	male
4828	kk_KZ	Zhuziya	female
4829	kk_KZ	Zhylkyshy	male
4830	kk_KZ	Zhyrgal	male
4831	kk_KZ	Ziba	female
4832	kk_KZ	Zibagul	female
4833	kk_KZ	Zibazhan	female
4834	kk_KZ	Zikibai	male
4835	kk_KZ	Zikiriya	male
4836	kk_KZ	Zila	female
4837	kk_KZ	Ziman	male
4838	kk_KZ	Zina	female
4839	kk_KZ	Zinaida	female
4840	kk_KZ	Zinara	female
4841	kk_KZ	Zinat	female
4842	kk_KZ	Zinira	female
4843	kk_KZ	Ziniya	female
4844	kk_KZ	Zira	female
4845	kk_KZ	Ziya	female
4846	kk_KZ	Ziyada	female
4847	kk_KZ	Ziyagul	female
4848	kk_KZ	Ziyakhan	female
4849	kk_KZ	Ziyaly	female
4850	kk_KZ	Ziyash	female
4851	kk_KZ	Ziyat	male
4852	kk_KZ	Ziyatbek	male
4853	kk_KZ	Zliman	female
4854	kk_KZ	Zore	female
4855	kk_KZ	Zoya	female
4856	kk_KZ	Zubaida	female
4857	kk_KZ	Zubaila	female
4858	kk_KZ	Zubaira	female
4859	kk_KZ	Zubaiza	female
4860	kk_KZ	Zukhra	female
4861	kk_KZ	Zulfiya	female
4862	kk_KZ	Zulipa	female
4863	kk_KZ	Zuliya	female
4864	kk_KZ	Zulkaiyr	male
4865	kk_KZ	Zulkash	male
4866	kk_KZ	Zulkiya	female
4867	kk_KZ	Zulpykar	male
4868	kk_KZ	Zumrat	female
4869	kk_KZ	Zuparzat	female
4870	kk_KZ	Zura	female
4871	kk_KZ	Zurash	female
4872	kk_KZ	Zykai	male
4873	kk_KZ	Zylika	female
4874	uz_UZ	A'zam	male
4875	uz_UZ	A'zamjon	male
4876	uz_UZ	A'zamoy	female
4877	uz_UZ	Abbos	male
4878	uz_UZ	Abbosa	female
4879	uz_UZ	Abdulaziz	male
4880	uz_UZ	Abdulboriy	male
4881	uz_UZ	Abdulbosit	male
4882	uz_UZ	Abdulfattoh	male
4883	uz_UZ	Abdulhamid	male
4884	uz_UZ	Abdulhaq	male
4885	uz_UZ	Abdulhay	male
4886	uz_UZ	Abdulla	male
4887	uz_UZ	Abdulloh	male
4888	uz_UZ	Abdulmajiddin	male
4889	uz_UZ	Abdulmalik	male
4890	uz_UZ	Abdulqodir	male
4891	uz_UZ	Abdulvahhob	male
4892	uz_UZ	Abdulvoris	male
4893	uz_UZ	Abdurahim	male
4894	uz_UZ	Abdurahmon	male
4895	uz_UZ	Abdurashid	male
4896	uz_UZ	Abdurauf	male
4897	uz_UZ	Abdusamad	male
4898	uz_UZ	Abdusami	male
4899	uz_UZ	Abdushukur	male
4900	uz_UZ	Abduvali	male
4901	uz_UZ	Abduvohid	male
4902	uz_UZ	Abror	male
4903	uz_UZ	Abubakr	male
4904	uz_UZ	Adham	male
4905	uz_UZ	Adiba	female
4906	uz_UZ	Adil	male
4907	uz_UZ	Adolat	female
4908	uz_UZ	Afifa	female
4909	uz_UZ	Afruz	female
4910	uz_UZ	Afruza	female
4911	uz_UZ	Afzal	male
4912	uz_UZ	Ahad	male
4913	uz_UZ	Ahadoy	female
4914	uz_UZ	Ahmad	male
4915	uz_UZ	Ahmadjon	male
4916	uz_UZ	Ahmadoy	female
4917	uz_UZ	Ahror	male
4918	uz_UZ	Aida	female
4919	uz_UZ	Ajdar	male
4920	uz_UZ	Akbar	male
4921	uz_UZ	Akmal	male
4922	uz_UZ	Akmaloy	female
4923	uz_UZ	Akram	male
4924	uz_UZ	Alavuddin	male
4925	uz_UZ	Alfiya	female
4926	uz_UZ	Ali	male
4927	uz_UZ	Alibek	male
4928	uz_UZ	Alima	female
4929	uz_UZ	Alimardon	male
4930	uz_UZ	Alisher	male
4931	uz_UZ	Amir	male
4932	uz_UZ	Amirbek	male
4933	uz_UZ	Amirxon	male
4934	uz_UZ	Anbara	female
4935	uz_UZ	Anbaroy	female
4936	uz_UZ	Anisa	female
4937	uz_UZ	Anora	female
4938	uz_UZ	Ansor	male
4939	uz_UZ	Anvar	male
4940	uz_UZ	Aqida	female
4941	uz_UZ	Aqiqa	female
4942	uz_UZ	Arjumand	female
4943	uz_UZ	Armug'on	female
4944	uz_UZ	Arofat	female
4945	uz_UZ	Arslon	male
4946	uz_UZ	Asad	male
4947	uz_UZ	Asadbek	male
4948	uz_UZ	Asadulla	male
4949	uz_UZ	Asal	female
4950	uz_UZ	Asaloy	female
4951	uz_UZ	Asil	male
4952	uz_UZ	Asila	female
4953	uz_UZ	Asilbek	male
4954	uz_UZ	Asiya	female
4955	uz_UZ	Asmira	female
4956	uz_UZ	Asmo	female
4957	uz_UZ	Asqar	male
4958	uz_UZ	Avaz	male
4959	uz_UZ	Ayub	male
4960	uz_UZ	Azim	male
4962	uz_UZ	Aziza	female
4963	uz_UZ	Azizabonu	female
4964	uz_UZ	Azizbek	male
4965	uz_UZ	Azmiddin	male
4966	uz_UZ	Bahodir	male
4967	uz_UZ	Bahora	female
4968	uz_UZ	Bahriddin	male
4969	uz_UZ	Bahriya	female
4970	uz_UZ	Bahrom	male
4971	uz_UZ	Bakir	male
4972	uz_UZ	Barchin	female
4973	uz_UZ	Barchinoy	female
4974	uz_UZ	Barlos	male
4975	uz_UZ	Barno	female
4976	uz_UZ	Barot	male
4977	uz_UZ	Basira	female
4978	uz_UZ	Batiy	male
4979	uz_UZ	Baxtigul	female
4980	uz_UZ	Baxtiniso	female
4981	uz_UZ	Baxtishod	male
4982	uz_UZ	Baxtiyor	male
4983	uz_UZ	Baxtiyoroy	female
4984	uz_UZ	Baxtliya	female
4985	uz_UZ	Begim	female
4986	uz_UZ	Begoyim	female
4987	uz_UZ	Behruz	male
4988	uz_UZ	Bek	male
4989	uz_UZ	Beka	female
4990	uz_UZ	Bekajon	female
4991	uz_UZ	Bekali	male
4992	uz_UZ	Bekmurod	male
4993	uz_UZ	Beknazar	male
4994	uz_UZ	Bekoyim	female
4995	uz_UZ	Bektemir	male
4996	uz_UZ	Bektosh	male
4997	uz_UZ	Bekzod	male
4998	uz_UZ	Berdibek	male
4999	uz_UZ	Bibi	female
5000	uz_UZ	Bibigul	female
5001	uz_UZ	Bibiniso	female
5002	uz_UZ	Bibisora	female
5003	uz_UZ	Bibixon	female
5004	uz_UZ	Bibizuhra	female
5005	uz_UZ	Bilol	male
5006	uz_UZ	Biloliddin	male
5007	uz_UZ	Bino	male
5008	uz_UZ	Binofsha	female
5009	uz_UZ	Bintu	female
5010	uz_UZ	Bo'ri	male
5011	uz_UZ	Bo'riboy	male
5012	uz_UZ	Bo'ston	female
5013	uz_UZ	Bo'stonoy	female
5014	uz_UZ	Bobo	male
5015	uz_UZ	Bobomurod	male
5016	uz_UZ	Bobur	male
5017	uz_UZ	Bodom	female
5018	uz_UZ	Bodomoy	female
5019	uz_UZ	Bonu	female
5020	uz_UZ	Botir	male
5021	uz_UZ	Bozor	male
5022	uz_UZ	Bozorboy	male
5023	uz_UZ	Bunyod	male
5024	uz_UZ	Burhon	male
5025	uz_UZ	Burhoniddin	male
5026	uz_UZ	Buvajon	female
5027	uz_UZ	Buvayim	female
5028	uz_UZ	Buzruk	male
5029	uz_UZ	Buzrukoy	female
5030	uz_UZ	Chingiz	male
5031	uz_UZ	Cho'lpon	male
5032	uz_UZ	Chori	male
5033	uz_UZ	Choriyor	male
5034	uz_UZ	Chorshanba	male
5035	uz_UZ	Daler	male
5036	uz_UZ	Dalil	male
5037	uz_UZ	Damir	male
5038	uz_UZ	Daniyal	male
5039	uz_UZ	Daryo	male
5040	uz_UZ	Davlat	male
5041	uz_UZ	Davlatbek	male
5042	uz_UZ	Davlatoy	female
5043	uz_UZ	Davron	male
5044	uz_UZ	Davronbek	male
5045	uz_UZ	Diba	female
5046	uz_UZ	Dilafro'z	female
5047	uz_UZ	Dilbar	female
5048	uz_UZ	Dilbaroy	female
5049	uz_UZ	Dildor	female
5050	uz_UZ	Dildora	female
5051	uz_UZ	Dilfuza	female
5052	uz_UZ	Dilmira	female
5053	uz_UZ	Dilmurod	male
5054	uz_UZ	Dilnavoz	female
5055	uz_UZ	Dilniyoz	female
5056	uz_UZ	Dilnoza	female
5057	uz_UZ	Dilnur	female
5058	uz_UZ	Dilnura	female
5059	uz_UZ	Dilorom	female
5060	uz_UZ	Dilrabo	female
5061	uz_UZ	Dilro'z	female
5062	uz_UZ	Dilsher	male
5063	uz_UZ	Dilshod	male
5064	uz_UZ	Dilshoda	female
5065	uz_UZ	Dilsora	female
5066	uz_UZ	Dilxiroj	female
5067	uz_UZ	Dilyora	female
5068	uz_UZ	Diydor	female
5069	uz_UZ	Diyora	female
5070	uz_UZ	Diyorbek	male
5071	uz_UZ	Do'stmat	male
5072	uz_UZ	Doniyor	male
5073	uz_UZ	Doston	male
5074	uz_UZ	Dostonbek	male
5075	uz_UZ	Durdi	male
5076	uz_UZ	Durdona	female
5077	uz_UZ	E'tibor	female
5078	uz_UZ	E'zoza	female
5079	uz_UZ	Egam	male
5080	uz_UZ	Egamberdi	male
5081	uz_UZ	Ehtishom	male
5082	uz_UZ	Ehtiyot	male
5083	uz_UZ	Elbek	male
5084	uz_UZ	Elboy	male
5085	uz_UZ	Elchi	male
5086	uz_UZ	Eldor	male
5087	uz_UZ	Elina	female
5088	uz_UZ	Elmira	female
5089	uz_UZ	Elnur	male
5090	uz_UZ	Elnura	female
5091	uz_UZ	Elshod	male
5092	uz_UZ	Elyor	male
5093	uz_UZ	Enaxon	female
5094	uz_UZ	Erali	male
5095	uz_UZ	Ergash	male
5096	uz_UZ	Erkin	male
5097	uz_UZ	Erkinjon	male
5098	uz_UZ	Erkinoy	female
5099	uz_UZ	Ermat	male
5100	uz_UZ	Eshmat	male
5101	uz_UZ	Eshmurod	male
5102	uz_UZ	Eshqobil	male
5103	uz_UZ	Eshqul	male
5104	uz_UZ	Eson	male
5105	uz_UZ	Esonoy	female
5106	uz_UZ	Fahriddin	male
5107	uz_UZ	Fahriniso	female
5108	uz_UZ	Farangiz	female
5109	uz_UZ	Faraxnoza	female
5110	uz_UZ	Farhod	male
5111	uz_UZ	Farida	female
5112	uz_UZ	Fariha	female
5113	uz_UZ	Farrux	male
5114	uz_UZ	Farxod	male
5115	uz_UZ	Faryod	male
5116	uz_UZ	Fathulla	male
5117	uz_UZ	Fattoh	male
5118	uz_UZ	Faxri	male
5119	uz_UZ	Faxriddin	male
5120	uz_UZ	Fayoza	female
5121	uz_UZ	Fayz	male
5122	uz_UZ	Fayzullo	male
5123	uz_UZ	Fazila	female
5124	uz_UZ	Fazilat	female
5125	uz_UZ	Fazliddin	male
5126	uz_UZ	Feruza	female
5127	uz_UZ	Fidan	female
5128	uz_UZ	Fido	female
5129	uz_UZ	Firdavs	male
5130	uz_UZ	Firuz	male
5131	uz_UZ	Firuza	female
5132	uz_UZ	Fotima	female
5133	uz_UZ	Fozil	male
5134	uz_UZ	Furqat	male
5135	uz_UZ	G'affor	male
5136	uz_UZ	G'afur	male
5137	uz_UZ	G'ayrat	male
5138	uz_UZ	G'azal	female
5139	uz_UZ	G'iyos	male
5140	uz_UZ	G'iyosiddin	male
5141	uz_UZ	G'olib	male
5142	uz_UZ	G'ulom	male
5143	uz_UZ	G'ulomqodir	male
5144	uz_UZ	Gado	male
5145	uz_UZ	Galdiboy	male
5146	uz_UZ	Ganj	male
5147	uz_UZ	Gavharoy	female
5148	uz_UZ	Gavharshod	female
5149	uz_UZ	Go'zal	female
5150	uz_UZ	Go'zaloy	female
5151	uz_UZ	Gul	female
5152	uz_UZ	Gulandom	female
5153	uz_UZ	Gulasal	female
5154	uz_UZ	Gulbadan	female
5155	uz_UZ	Gulbahor	female
5156	uz_UZ	Gulbarchin	female
5157	uz_UZ	Gulchehra	female
5158	uz_UZ	Gulchiroy	female
5159	uz_UZ	Guldasta	female
5160	uz_UZ	Guldira	female
5161	uz_UZ	Gulhayo	female
5162	uz_UZ	Guli	female
5163	uz_UZ	Gulinur	female
5164	uz_UZ	Gulira	female
5165	uz_UZ	Guliston	female
5166	uz_UZ	Guljahon	female
5167	uz_UZ	Guljamol	female
5168	uz_UZ	Gullola	female
5169	uz_UZ	Gulmira	female
5170	uz_UZ	Gulnavoz	female
5171	uz_UZ	Gulnigor	female
5172	uz_UZ	Gulniso	female
5173	uz_UZ	Gulnoza	female
5174	uz_UZ	Gulnura	female
5175	uz_UZ	Guloy	female
5176	uz_UZ	Guloyim	female
5177	uz_UZ	Gulparchin	female
5178	uz_UZ	Gulqiz	female
5179	uz_UZ	Gulra'no	female
5180	uz_UZ	Gulrux	female
5181	uz_UZ	Gulruxsor	female
5182	uz_UZ	Gulsanam	female
5183	uz_UZ	Gulshan	female
5184	uz_UZ	Gulshoda	female
5185	uz_UZ	Gulsora	female
5186	uz_UZ	Gultoj	female
5187	uz_UZ	Gulyor	female
5188	uz_UZ	Gulyuz	female
5189	uz_UZ	Gulzamon	female
5190	uz_UZ	Gulzira	female
5191	uz_UZ	Gulzoda	female
5192	uz_UZ	Habib	male
5193	uz_UZ	Habiba	female
5194	uz_UZ	Habibulla	male
5195	uz_UZ	Hadya	female
5196	uz_UZ	Hafiza	female
5197	uz_UZ	Hakim	male
5198	uz_UZ	Halim	male
5199	uz_UZ	Halima	female
5200	uz_UZ	Halovati	female
5201	uz_UZ	Hamid	male
5202	uz_UZ	Hamida	female
5203	uz_UZ	Hamidulla	male
5204	uz_UZ	Hanifa	female
5205	uz_UZ	Hasan	male
5206	uz_UZ	Hasana	female
5207	uz_UZ	Hasanboy	male
5208	uz_UZ	Havvo	female
5209	uz_UZ	Haydar	male
5210	uz_UZ	Hayit	male
5211	uz_UZ	Hayitboy	male
5212	uz_UZ	Hayitmat	male
5213	uz_UZ	Hayotxon	female
5214	uz_UZ	Hazina	female
5215	uz_UZ	Hiba	female
5216	uz_UZ	Hidoyat	female
5217	uz_UZ	Hikmat	male
5218	uz_UZ	Hikmatulla	male
5219	uz_UZ	Hilol	male
5220	uz_UZ	Hilola	female
5221	uz_UZ	Himmat	male
5222	uz_UZ	Hojar	female
5223	uz_UZ	Holida	female
5224	uz_UZ	Horiya	female
5225	uz_UZ	Hoshim	male
5226	uz_UZ	Humora	female
5227	uz_UZ	Humoyun	male
5228	uz_UZ	Hunar	female
5229	uz_UZ	Huriniso	female
5230	uz_UZ	Hurliqo	female
5231	uz_UZ	Hurmat	female
5232	uz_UZ	Husan	male
5233	uz_UZ	Husanboy	male
5234	uz_UZ	Husayn	male
5235	uz_UZ	Husniya	female
5236	uz_UZ	Ibodat	female
5237	uz_UZ	Ibrohim	male
5238	uz_UZ	Idrok	male
5239	uz_UZ	Iffat	female
5240	uz_UZ	Iftixor	male
5241	uz_UZ	Ijoza	female
5242	uz_UZ	Ikrom	male
5243	uz_UZ	Ilhom	male
5244	uz_UZ	Ilmira	female
5245	uz_UZ	Iltifot	female
5246	uz_UZ	Ilyos	male
5247	uz_UZ	Imom	male
5248	uz_UZ	Imomali	male
5249	uz_UZ	Imomiddin	male
5250	uz_UZ	Imon	male
5251	uz_UZ	Imona	female
5252	uz_UZ	Imron	male
5253	uz_UZ	In'om	male
5254	uz_UZ	Inobat	female
5255	uz_UZ	Inoyat	female
5256	uz_UZ	Ipak	female
5257	uz_UZ	Iqbol	female
5258	uz_UZ	Iroda	female
5259	uz_UZ	Islom	male
5260	uz_UZ	Islomiddin	male
5261	uz_UZ	Ismat	male
5262	uz_UZ	Ismatulla	male
5263	uz_UZ	Ismoil	male
5264	uz_UZ	Isroil	male
5265	uz_UZ	Istam	female
5266	uz_UZ	Istarbeka	female
5267	uz_UZ	Iste'dod	male
5268	uz_UZ	Ixtiyor	male
5269	uz_UZ	Izzat	male
5270	uz_UZ	Izzatulla	male
5271	uz_UZ	Jabbor	male
5272	uz_UZ	Jafar	male
5273	uz_UZ	Jahon	male
5274	uz_UZ	Jahona	female
5275	uz_UZ	Jahongir	male
5276	uz_UZ	Jahongul	female
5277	uz_UZ	Jalil	male
5278	uz_UZ	Jalol	male
5279	uz_UZ	Jaloliddin	male
5280	uz_UZ	Jamila	female
5281	uz_UZ	Jamilaxon	female
5282	uz_UZ	Jamol	male
5283	uz_UZ	Jamoliddin	male
5284	uz_UZ	Jamshid	male
5285	uz_UZ	Jannat	female
5286	uz_UZ	Jasmina	female
5287	uz_UZ	Jasur	male
5288	uz_UZ	Jasurbek	male
5289	uz_UZ	Javlon	male
5290	uz_UZ	Javohir	male
5291	uz_UZ	Javohira	female
5292	uz_UZ	Jayrona	female
5293	uz_UZ	Jiyan	male
5294	uz_UZ	Jiyanboy	male
5295	uz_UZ	Jiyda	female
5296	uz_UZ	Jo'ra	male
5297	uz_UZ	Jo'rabek	male
5298	uz_UZ	Jo'raboy	male
5299	uz_UZ	Jomurod	male
5300	uz_UZ	Jumabika	female
5301	uz_UZ	Jumaboy	male
5302	uz_UZ	Jumanazar	male
5303	uz_UZ	Jumaniyoz	male
5304	uz_UZ	Kamila	female
5305	uz_UZ	Kamol	male
5307	uz_UZ	Kamoliddin	male
5308	uz_UZ	Karim	male
5309	uz_UZ	Karima	female
5310	uz_UZ	Karimberdi	male
5311	uz_UZ	Karomiddin	male
5312	uz_UZ	Kasim	male
5313	uz_UZ	Kausar	female
5314	uz_UZ	Kavsar	female
5315	uz_UZ	Keldiyor	male
5316	uz_UZ	Kenja	male
5317	uz_UZ	Kenjaboy	male
5318	uz_UZ	Kibriyo	female
5319	uz_UZ	Kimsan	male
5320	uz_UZ	Kimsanboy	male
5321	uz_UZ	Kimsanoy	female
5322	uz_UZ	Kobil	male
5323	uz_UZ	Kofiya	female
5324	uz_UZ	Komil	male
5325	uz_UZ	Komila	female
5326	uz_UZ	Komron	male
5327	uz_UZ	Kozim	male
5328	uz_UZ	Kumush	female
5329	uz_UZ	Kumushoy	female
5330	uz_UZ	Kunniso	female
5331	uz_UZ	Latif	male
5332	uz_UZ	Latifa	female
5333	uz_UZ	Layli	female
5334	uz_UZ	Laylo	female
5335	uz_UZ	Laziz	male
5336	uz_UZ	Laziza	female
5337	uz_UZ	Lobar	female
5338	uz_UZ	Lochin	male
5339	uz_UZ	Lochinbek	male
5340	uz_UZ	Lola	female
5341	uz_UZ	Lolazor	female
5342	uz_UZ	Luqmon	male
5343	uz_UZ	Lutfiddin	male
5344	uz_UZ	Lutfiya	female
5345	uz_UZ	Lutfiyya	female
5346	uz_UZ	Lutfnniso	female
5347	uz_UZ	Lutfullo	male
5348	uz_UZ	Ma'ruf	male
5349	uz_UZ	Ma'sud	male
5350	uz_UZ	Madamin	male
5351	uz_UZ	Madiha	female
5352	uz_UZ	Madina	female
5353	uz_UZ	Madinabonu	female
5354	uz_UZ	Maftuna	female
5355	uz_UZ	Mahbuba	female
5356	uz_UZ	Mahdiyya	female
5357	uz_UZ	Mahfuza	female
5358	uz_UZ	Mahliyo	female
5359	uz_UZ	Mahmud	male
5360	uz_UZ	Mahmudaxon	female
5361	uz_UZ	Mahmudjon	male
5362	uz_UZ	Mahzuna	female
5363	uz_UZ	Majid	male
5364	uz_UZ	Majiddin	male
5365	uz_UZ	Makam	male
5366	uz_UZ	Maksad	male
5367	uz_UZ	Malahat	female
5369	uz_UZ	Malikabonu	female
5370	uz_UZ	Mamarayim	male
5371	uz_UZ	Mamasoli	male
5372	uz_UZ	Mamat	male
5373	uz_UZ	Mamatqul	male
5374	uz_UZ	Mamatraim	male
5375	uz_UZ	Mamlakat	female
5376	uz_UZ	Manija	female
5377	uz_UZ	Mansur	male
5378	uz_UZ	Mansura	female
5379	uz_UZ	Manzur	male
5380	uz_UZ	Manzura	female
5381	uz_UZ	Mardon	male
5382	uz_UZ	Mardonbek	male
5383	uz_UZ	Marhabo	female
5384	uz_UZ	Marjona	female
5385	uz_UZ	Maryam	female
5386	uz_UZ	Mashhura	female
5387	uz_UZ	Mashrab	male
5388	uz_UZ	Mastura	female
5389	uz_UZ	Matchon	male
5390	uz_UZ	Mavluda	female
5391	uz_UZ	Maxfira	female
5392	uz_UZ	Maxmud	male
5393	uz_UZ	Maxsud	male
5394	uz_UZ	Maydon	male
5395	uz_UZ	Medina	female
5396	uz_UZ	Mehrangiz	female
5397	uz_UZ	Mehribon	female
5398	uz_UZ	Mehriddin	male
5399	uz_UZ	Mehrigiya	female
5400	uz_UZ	Mehrigul	female
5401	uz_UZ	Mehriniso	female
5402	uz_UZ	Mehrinur	female
5403	uz_UZ	Meli	male
5404	uz_UZ	Meliboy	male
5405	uz_UZ	Melisa	female
5406	uz_UZ	Mengziyo	male
5407	uz_UZ	Meva	female
5408	uz_UZ	Minavvar	female
5409	uz_UZ	Minhoj	male
5410	uz_UZ	Mirkamol	male
5411	uz_UZ	Mirshod	male
5412	uz_UZ	Mirzo	male
5413	uz_UZ	Mirzobek	male
5414	uz_UZ	Mirzohid	male
5415	uz_UZ	Mirzoyim	female
5416	uz_UZ	Mohi	female
5417	uz_UZ	Mohichehra	female
5418	uz_UZ	Mohidil	female
5419	uz_UZ	Mohigul	female
5420	uz_UZ	Mohinur	female
5421	uz_UZ	Mohira	female
5422	uz_UZ	Mohitabon	female
5423	uz_UZ	Muattar	female
5424	uz_UZ	Muborak	female
5425	uz_UZ	Muhabbat	female
5426	uz_UZ	Muhammad	male
5427	uz_UZ	Muhammadali	male
5428	uz_UZ	Muhammadamin	male
5429	uz_UZ	Muhammadjon	male
5430	uz_UZ	Muhammadkarim	male
5431	uz_UZ	Muhammadqodir	male
5432	uz_UZ	Muhammadsodiq	male
5433	uz_UZ	Muhammadumar	male
5434	uz_UZ	Muhaymin	female
5435	uz_UZ	Muhayyo	female
5436	uz_UZ	Muhiba	female
5437	uz_UZ	Muhiddin	male
5438	uz_UZ	Muhtaram	female
5439	uz_UZ	Muhtor	male
5440	uz_UZ	Mukarram	female
5441	uz_UZ	Muloqot	female
5442	uz_UZ	Mumtoz	female
5443	uz_UZ	Mumtozbegim	female
5444	uz_UZ	Munavvar	female
5445	uz_UZ	Munira	female
5446	uz_UZ	Munisa	female
5447	uz_UZ	Muqaddas	female
5448	uz_UZ	Murod	male
5449	uz_UZ	Murodilla	male
5450	uz_UZ	Murodoy	female
5451	uz_UZ	Muslima	female
5452	uz_UZ	Muso	male
5453	uz_UZ	Mutabar	female
5454	uz_UZ	Muyassar	female
5455	uz_UZ	Muzaffar	male
5456	uz_UZ	Muzaffara	female
5457	uz_UZ	Nabi	male
5458	uz_UZ	Nabira	female
5459	uz_UZ	Nadira	female
5460	uz_UZ	Nafisa	female
5461	uz_UZ	Nahida	female
5462	uz_UZ	Najiba	female
5463	uz_UZ	Najim	male
5464	uz_UZ	Najiya	female
5465	uz_UZ	Najmiddin	male
5466	uz_UZ	Najmiddinoy	female
5467	uz_UZ	Namanganoy	female
5468	uz_UZ	Namoz	male
5469	uz_UZ	Naqiba	female
5470	uz_UZ	Nargis	female
5471	uz_UZ	Nargiza	female
5472	uz_UZ	Narima	female
5473	uz_UZ	Narimon	male
5474	uz_UZ	Nasiba	female
5475	uz_UZ	Nasiha	female
5476	uz_UZ	Nasim	male
5477	uz_UZ	Nasiya	female
5478	uz_UZ	Nasriddin	male
5479	uz_UZ	Nasridinoy	female
5480	uz_UZ	Nasullo	male
5481	uz_UZ	Natija	female
5482	uz_UZ	Navbahor	female
5483	uz_UZ	Navro'z	male
5484	uz_UZ	Navro'za	female
5485	uz_UZ	Nazar	male
5486	uz_UZ	Nazarali	male
5487	uz_UZ	Nazari	female
5488	uz_UZ	Nazifa	female
5489	uz_UZ	Nazira	female
5490	uz_UZ	Nazokat	female
5491	uz_UZ	Ne'mat	male
5492	uz_UZ	Ne'matoy	female
5493	uz_UZ	Ne'matullo	male
5494	uz_UZ	Nigina	female
5495	uz_UZ	Nigora	female
5496	uz_UZ	Nigoroy	female
5497	uz_UZ	Nihol	female
5498	uz_UZ	Nihola	female
5499	uz_UZ	Nilufar	female
5500	uz_UZ	Niso	female
5501	uz_UZ	Niyoz	male
5502	uz_UZ	Niyozxon	female
5503	uz_UZ	Nizom	male
5504	uz_UZ	Nizomiddin	male
5505	uz_UZ	Nizomoy	female
5507	uz_UZ	Nodir	male
5508	uz_UZ	Nodira	female
5509	uz_UZ	Nodirabegim	female
5510	uz_UZ	Nodirbek	male
5511	uz_UZ	Noila	female
5512	uz_UZ	Nola	female
5513	uz_UZ	Norgul	female
5514	uz_UZ	Noriniso	female
5515	uz_UZ	Noriya	female
5516	uz_UZ	Norposhsha	female
5517	uz_UZ	Nosir	male
5518	uz_UZ	Notoj	female
5519	uz_UZ	Noza	female
5520	uz_UZ	Nozanin	female
5521	uz_UZ	Nozi	female
5522	uz_UZ	Nozigul	female
5523	uz_UZ	Nozim	male
5524	uz_UZ	Nozima	female
5525	uz_UZ	Nuh	male
5526	uz_UZ	Nuqra	female
5527	uz_UZ	Nurafshon	female
5528	uz_UZ	Nurali	male
5529	uz_UZ	Nurberdi	male
5530	uz_UZ	Nurbibi	female
5531	uz_UZ	Nurgul	female
5532	uz_UZ	Nurida	female
5533	uz_UZ	Nuriddin	male
5534	uz_UZ	Nurillo	male
5535	uz_UZ	Nurislom	male
5536	uz_UZ	Nuriya	female
5537	uz_UZ	Nurjahon	female
5538	uz_UZ	Nurligul	female
5539	uz_UZ	Nurmat	male
5540	uz_UZ	Nurmuhammad	male
5541	uz_UZ	Nurniso	female
5542	uz_UZ	Nusrat	female
5543	uz_UZ	Nusriddin	male
5544	uz_UZ	O'g'il	female
5545	uz_UZ	O'g'iloy	female
5546	uz_UZ	O'g'ilshod	female
5547	uz_UZ	O'ktam	male
5548	uz_UZ	O'ktamoy	female
5549	uz_UZ	O'lmas	male
5550	uz_UZ	O'lmasoy	female
5551	uz_UZ	O'rin	male
5552	uz_UZ	O'rinboy	male
5553	uz_UZ	O'rinoy	female
5554	uz_UZ	O'roz	male
5555	uz_UZ	O'rozboy	male
5556	uz_UZ	O'rozoy	female
5557	uz_UZ	O'tkir	male
5558	uz_UZ	O'tkirbek	male
5559	uz_UZ	O'zbekoy	female
5560	uz_UZ	Obid	male
5561	uz_UZ	Obida	female
5562	uz_UZ	Obidjon	male
5563	uz_UZ	Odil	male
5564	uz_UZ	Odila	female
5565	uz_UZ	Odiljon	male
5566	uz_UZ	Odina	female
5567	uz_UZ	Ofarin	female
5568	uz_UZ	Oftob	female
5569	uz_UZ	Oftoboy	female
5570	uz_UZ	Og'abegim	female
5571	uz_UZ	Og'abek	male
5572	uz_UZ	Og'ocha	female
5573	uz_UZ	Oisha	female
5574	uz_UZ	Okhun	male
5575	uz_UZ	Oksan	male
5576	uz_UZ	Olia	female
5577	uz_UZ	Olim	male
5578	uz_UZ	Olima	female
5579	uz_UZ	Olimjon	male
5580	uz_UZ	Oliy	male
5581	uz_UZ	Oliyabonu	female
5582	uz_UZ	Olma	female
5583	uz_UZ	Olmaoy	female
5584	uz_UZ	Olmos	female
5585	uz_UZ	Olmosoy	female
5586	uz_UZ	Olovuddin	male
5587	uz_UZ	Ominaxon	female
5588	uz_UZ	Omon	male
5589	uz_UZ	Omonoy	female
5590	uz_UZ	Omonullo	male
5591	uz_UZ	Oqil	male
5592	uz_UZ	Oqiljon	male
5593	uz_UZ	Orasta	female
5594	uz_UZ	Oriba	female
5595	uz_UZ	Oribaxon	female
5596	uz_UZ	Orif	male
5597	uz_UZ	Orifa	female
5598	uz_UZ	Orip	male
5599	uz_UZ	Orom	female
5600	uz_UZ	Oromdil	female
5601	uz_UZ	Oromgul	female
5602	uz_UZ	Ortiq	male
5603	uz_UZ	Orzigul	female
5604	uz_UZ	Orziya	female
5605	uz_UZ	Orzu	female
5606	uz_UZ	Orzugul	female
5607	uz_UZ	Orzumurod	male
5608	uz_UZ	Otabek	male
5609	uz_UZ	Otajon	male
5610	uz_UZ	Otkir	male
5611	uz_UZ	Oybadam	female
5612	uz_UZ	Oybarchin	female
5613	uz_UZ	Oybek	male
5614	uz_UZ	Oybeka	female
5615	uz_UZ	Oybibi	female
5616	uz_UZ	Oybu	female
5617	uz_UZ	Oydin	female
5618	uz_UZ	Oydinoy	female
5619	uz_UZ	Oyfon	female
5620	uz_UZ	Oygul	female
5621	uz_UZ	Oyim	female
5622	uz_UZ	Oyimqiz	female
5623	uz_UZ	Oyimtoj	female
5624	uz_UZ	Oyina	female
5625	uz_UZ	Oyjamol	female
5626	uz_UZ	Oynisa	female
5627	uz_UZ	Oyniso	female
5628	uz_UZ	Oyparcha	female
5629	uz_UZ	Oypopuk	female
5630	uz_UZ	Oyqiz	female
5631	uz_UZ	Oysara	female
5632	uz_UZ	Oysha	female
5633	uz_UZ	Oytijar	female
5634	uz_UZ	Oyto'ra	female
5635	uz_UZ	Ozod	male
5636	uz_UZ	Ozoda	female
5637	uz_UZ	Ozodbek	male
5638	uz_UZ	Pahlavon	male
5639	uz_UZ	Panji	male
5640	uz_UZ	Parizod	female
5641	uz_UZ	Parizoda	female
5642	uz_UZ	Parvina	female
5643	uz_UZ	Parviz	male
5644	uz_UZ	Paymona	female
5645	uz_UZ	Payzullo	male
5646	uz_UZ	Pazliddin	male
5647	uz_UZ	Piroza	female
5648	uz_UZ	Po'lat	male
5649	uz_UZ	Po'latjon	male
5650	uz_UZ	Po'lkan	male
5651	uz_UZ	Pokiza	female
5652	uz_UZ	Polvon	male
5653	uz_UZ	Polvonboy	male
5654	uz_UZ	Popuk	female
5655	uz_UZ	Poshshaxon	female
5656	uz_UZ	Prim	male
5657	uz_UZ	Qadriya	female
5658	uz_UZ	Qahhor	male
5659	uz_UZ	Qahramon	male
5660	uz_UZ	Qalandar	male
5661	uz_UZ	Qaldirg'och	female
5662	uz_UZ	Qamar	female
5663	uz_UZ	Qamariddin	male
5664	uz_UZ	Qambr	male
5665	uz_UZ	Qandolat	female
5666	uz_UZ	Qarshi	male
5667	uz_UZ	Qashqar	male
5668	uz_UZ	Qaytar	female
5669	uz_UZ	Qayum	male
5670	uz_UZ	Qilich	male
5671	uz_UZ	Qilichbek	male
5672	uz_UZ	Qimmat	female
5673	uz_UZ	Qimmatoy	female
5674	uz_UZ	Qizlarxon	female
5675	uz_UZ	Qo'chqor	male
5676	uz_UZ	Qo'ldosh	male
5677	uz_UZ	Qobil	male
5678	uz_UZ	Qobul	male
5679	uz_UZ	Qodir	male
5680	uz_UZ	Qodirjon	male
5681	uz_UZ	Qoldosh	male
5682	uz_UZ	Qori	male
5683	uz_UZ	Qosim	male
5684	uz_UZ	Qosimali	male
5685	uz_UZ	Qudrat	male
5686	uz_UZ	Qudratilla	male
5687	uz_UZ	Qudratoy	female
5688	uz_UZ	Qurbon	male
5689	uz_UZ	Qurbonali	male
5690	uz_UZ	Qurbonoy	female
5691	uz_UZ	Qutbiya	female
5692	uz_UZ	Qutli	female
5693	uz_UZ	Ra'no	female
5694	uz_UZ	Ra'nogul	female
5695	uz_UZ	Rabbani	male
5696	uz_UZ	Rabboniy	female
5697	uz_UZ	Raddiya	female
5698	uz_UZ	Rafig'a	female
5699	uz_UZ	Rafina	female
5700	uz_UZ	Rahbar	female
5701	uz_UZ	Rahim	male
5702	uz_UZ	Rahima	female
5703	uz_UZ	Rahimaoy	female
5704	uz_UZ	Rahimberdi	male
5705	uz_UZ	Rahimboy	male
5706	uz_UZ	Rahmat	male
5707	uz_UZ	Rahmatilla	male
5708	uz_UZ	Rahmatullo	male
5709	uz_UZ	Rahmon	male
5710	uz_UZ	Rahmonberdi	male
5711	uz_UZ	Rajab	male
5712	uz_UZ	Rajabboy	male
5713	uz_UZ	Ramazon	male
5714	uz_UZ	Ramiz	male
5715	uz_UZ	Ramziddin	male
5716	uz_UZ	Rasima	female
5717	uz_UZ	Rasul	male
5718	uz_UZ	Rasulbek	male
5719	uz_UZ	Ravshan	male
5720	uz_UZ	Ravshanbek	male
5721	uz_UZ	Rayhona	female
5722	uz_UZ	Rayim	male
5723	uz_UZ	Razzoqa	female
5724	uz_UZ	Rixsiboy	male
5725	uz_UZ	Rixsixon	female
5726	uz_UZ	Rizvongul	female
5727	uz_UZ	Ro'zi	male
5728	uz_UZ	Ro'ziboy	male
5729	uz_UZ	Ro'zigul	female
5730	uz_UZ	Ro'zimat	male
5731	uz_UZ	Ro'zimurod	male
5732	uz_UZ	Ro'ziqul	male
5733	uz_UZ	Ro'ziya	female
5734	uz_UZ	Robiya	female
5735	uz_UZ	Rohat	female
5736	uz_UZ	Roksana	female
5737	uz_UZ	Roziya	female
5738	uz_UZ	Ruhshona	female
5739	uz_UZ	Rumina	female
5740	uz_UZ	Ruqiya	female
5741	uz_UZ	Rustam	male
5742	uz_UZ	Rustambek	male
5743	uz_UZ	Ruxshona	female
5744	uz_UZ	Ruxsora	female
5745	uz_UZ	Ruzdor	male
5746	uz_UZ	Sa'dulla	male
5747	uz_UZ	Sabina	female
5748	uz_UZ	Sabo	female
5749	uz_UZ	Sabohat	female
5750	uz_UZ	Sabohiddin	male
5751	uz_UZ	Sadoqat	female
5752	uz_UZ	Sadriddin	male
5753	uz_UZ	Safar	male
5754	uz_UZ	Safarali	male
5755	uz_UZ	Safina	female
5756	uz_UZ	Safiya	female
5757	uz_UZ	Sahar	female
5758	uz_UZ	Sahbo	female
5759	uz_UZ	Sahob	male
5760	uz_UZ	Sahobiddin	male
5761	uz_UZ	Said	male
5762	uz_UZ	Saida	female
5763	uz_UZ	Saidabonu	female
5764	uz_UZ	Saidakbar	male
5765	uz_UZ	Saidali	male
5766	uz_UZ	Saidazim	male
5767	uz_UZ	Saidjalol	male
5768	uz_UZ	Saidjamol	male
5769	uz_UZ	Saidkamol	male
5770	uz_UZ	Saidmurod	male
5771	uz_UZ	Sajida	female
5772	uz_UZ	Salay	male
5773	uz_UZ	Salim	male
5774	uz_UZ	Salima	female
5775	uz_UZ	Saliqa	female
5776	uz_UZ	Samad	male
5777	uz_UZ	Samandar	male
5778	uz_UZ	Samat	male
5779	uz_UZ	Sami	male
5780	uz_UZ	Samina	female
5781	uz_UZ	Samira	female
5782	uz_UZ	San'at	male
5783	uz_UZ	Sana	female
5784	uz_UZ	Sanam	female
5785	uz_UZ	Saniqa	female
5786	uz_UZ	Sanjar	male
5787	uz_UZ	Sanjarbek	male
5788	uz_UZ	Sanobar	female
5789	uz_UZ	Saodat	female
5790	uz_UZ	Sarbinaz	female
5791	uz_UZ	Sarbon	male
5792	uz_UZ	Sarchashma	female
5794	uz_UZ	Sardorbek	male
5795	uz_UZ	Sarvar	male
5796	uz_UZ	Sarvarbek	male
5797	uz_UZ	Sarvinoz	female
5798	uz_UZ	Satira	female
5799	uz_UZ	Sattoroy	female
5800	uz_UZ	Sayfiddin	male
5801	uz_UZ	Sayfullo	male
5802	uz_UZ	Sevara	female
5803	uz_UZ	Sevinch	female
5804	uz_UZ	Shafoat	male
5805	uz_UZ	Shahboz	male
5806	uz_UZ	Shahlo	female
5807	uz_UZ	Shahnoza	female
5808	uz_UZ	Shahob	male
5809	uz_UZ	Shahobiddin	male
5810	uz_UZ	Shahodat	female
5811	uz_UZ	Shahribonu	female
5812	uz_UZ	Shahriyor	male
5813	uz_UZ	Shahrizoda	female
5814	uz_UZ	Shahzod	male
5815	uz_UZ	Shahzoda	female
5816	uz_UZ	Shakir	male
5817	uz_UZ	Shamim	female
5818	uz_UZ	Shamsi	male
5819	uz_UZ	Shamsiddin	male
5820	uz_UZ	Shamsiya	female
5821	uz_UZ	Sharifa	female
5822	uz_UZ	Sharof	male
5823	uz_UZ	Sharofat	female
5824	uz_UZ	Sharofiddin	male
5825	uz_UZ	Shavkat	male
5826	uz_UZ	Shaydo	female
5827	uz_UZ	Sher	male
5828	uz_UZ	Sherali	male
5829	uz_UZ	Sherzod	male
5830	uz_UZ	Sherzodbek	male
5831	uz_UZ	Shifo	male
5832	uz_UZ	Shirin	female
5833	uz_UZ	Shirinoy	female
5834	uz_UZ	Shiroq	male
5835	uz_UZ	Shodiya	female
5836	uz_UZ	Shodiyor	male
5837	uz_UZ	Shodmon	male
5838	uz_UZ	Shodmonoy	female
5839	uz_UZ	Shohida	female
5840	uz_UZ	Shohista	female
5841	uz_UZ	Shohjahon	male
5842	uz_UZ	Shohmurod	male
5843	uz_UZ	Shohruh	male
5844	uz_UZ	Shohruhbek	male
5845	uz_UZ	Shohsanam	female
5846	uz_UZ	Shoira	female
5847	uz_UZ	Shokir	male
5848	uz_UZ	Shoxista	female
5849	uz_UZ	Shuhrat	male
5850	uz_UZ	Shuhratbek	male
5851	uz_UZ	Shukur	male
5852	uz_UZ	Shukurullo	male
5853	uz_UZ	Shukurxon	female
5854	uz_UZ	Sitora	female
5855	uz_UZ	Sobir	male
5856	uz_UZ	Sodiq	male
5857	uz_UZ	Sodiqjon	male
5858	uz_UZ	Sohib	male
5859	uz_UZ	Sohibjamol	female
5860	uz_UZ	Sojida	female
5861	uz_UZ	Soraxon	female
5862	uz_UZ	Suhrob	male
5863	uz_UZ	Sulaymon	male
5864	uz_UZ	Sulton	male
5865	uz_UZ	Sultonali	male
5866	uz_UZ	Sultonmurod	male
5867	uz_UZ	Sunnat	male
5868	uz_UZ	Sunnatilla	male
5869	uz_UZ	Suyun	male
5870	uz_UZ	Tabassum	female
5871	uz_UZ	Tabriz	male
5872	uz_UZ	Tanti	female
5873	uz_UZ	Temur	male
5874	uz_UZ	Temurbek	male
5875	uz_UZ	Temurmalik	male
5876	uz_UZ	Tesha	male
5877	uz_UZ	Tilov	male
5878	uz_UZ	Tirkash	male
5879	uz_UZ	To'lqin	male
5880	uz_UZ	To'lqinoy	female
5881	uz_UZ	To'ra	male
5882	uz_UZ	To'rabek	male
5883	uz_UZ	To'ychi	male
5884	uz_UZ	Tohir	male
5885	uz_UZ	Toir	male
5886	uz_UZ	Tojbar	female
5887	uz_UZ	Tojiddin	male
5888	uz_UZ	Tojiniso	female
5889	uz_UZ	Tojixon	female
5890	uz_UZ	Tolib	male
5891	uz_UZ	Tomaris	female
5892	uz_UZ	Tosh	male
5893	uz_UZ	Toshmat	male
5894	uz_UZ	Toshmurod	male
5895	uz_UZ	Toshpo'lat	male
5896	uz_UZ	Turdali	male
5897	uz_UZ	Turdi	male
5898	uz_UZ	Turdimurod	male
5899	uz_UZ	Tursun	male
5900	uz_UZ	Tursunali	male
5901	uz_UZ	Tursunboy	male
5902	uz_UZ	Tursunoy	female
5903	uz_UZ	Tursunxon	female
5904	uz_UZ	Ubay	male
5905	uz_UZ	Ubayda	female
5906	uz_UZ	Ubaydulla	male
5907	uz_UZ	Ulgi	female
5908	uz_UZ	Ulug'bek	male
5909	uz_UZ	Ulug'oy	female
5910	uz_UZ	Umar	male
5911	uz_UZ	Umarali	male
5912	uz_UZ	Umarxon	male
5913	uz_UZ	Umid	male
5914	uz_UZ	Umida	female
5915	uz_UZ	Umidjon	male
5916	uz_UZ	Umiya	female
5917	uz_UZ	Umniya	female
5918	uz_UZ	Usmon	male
5919	uz_UZ	Usmonali	male
5920	uz_UZ	Usmonjon	male
5921	uz_UZ	Usta	male
5922	uz_UZ	Ustaqiz	female
5923	uz_UZ	Uyg'un	male
5924	uz_UZ	Uzoq	male
5925	uz_UZ	Uzoqboy	male
5926	uz_UZ	Vahhob	male
5927	uz_UZ	Vahob	male
5928	uz_UZ	Vali	male
5929	uz_UZ	Valida	female
5930	uz_UZ	Valijon	male
5931	uz_UZ	Vasila	female
5932	uz_UZ	Vasliddin	male
5933	uz_UZ	Vazira	female
5934	uz_UZ	Viloyat	female
5935	uz_UZ	Vohid	male
5936	uz_UZ	Vohidjon	male
5937	uz_UZ	Voris	male
5938	uz_UZ	Xabib	male
5939	uz_UZ	Xadicha	female
5940	uz_UZ	Xalil	male
5941	uz_UZ	Xalima	female
5942	uz_UZ	Xalos	female
5943	uz_UZ	Xalq	male
5944	uz_UZ	Xanifa	female
5945	uz_UZ	Xasiyat	female
5946	uz_UZ	Xayri	female
5947	uz_UZ	Xayriniso	female
5948	uz_UZ	Xayrulla	male
5949	uz_UZ	Xidoyat	male
5950	uz_UZ	Xislat	male
5951	uz_UZ	Xolbek	male
5952	uz_UZ	Xolbibi	female
5953	uz_UZ	Xolboy	male
5954	uz_UZ	Xoldor	male
5955	uz_UZ	Xoliqa	female
5956	uz_UZ	Xolmat	male
5957	uz_UZ	Xolmurod	male
5958	uz_UZ	Xolnisa	female
5959	uz_UZ	Xolto'ra	male
5960	uz_UZ	Xondamir	male
5961	uz_UZ	Xonim	male
5962	uz_UZ	Xos	male
5963	uz_UZ	Xosiyat	female
5964	uz_UZ	Xosiyatxon	female
5965	uz_UZ	Xudoyberdi	male
5966	uz_UZ	Xudoynazar	male
5967	uz_UZ	Xumora	female
5968	uz_UZ	Xurram	male
5969	uz_UZ	Xurshid	male
5970	uz_UZ	Xurshida	female
5971	uz_UZ	Yahyo	male
5972	uz_UZ	Yamin	male
5973	uz_UZ	Yarat	male
5974	uz_UZ	Yaxshi	male
5975	uz_UZ	Yaxshiboy	male
5976	uz_UZ	Yayra	female
5977	uz_UZ	Yigitali	male
5978	uz_UZ	Yo'lchi	male
5979	uz_UZ	Yo'ldosh	male
5980	uz_UZ	Yo'ldoshali	male
5981	uz_UZ	Yodgor	male
5982	uz_UZ	Yoqub	male
5983	uz_UZ	Yormurod	male
5984	uz_UZ	Yorqin	male
5985	uz_UZ	Yulduz	female
5986	uz_UZ	Yulduzoy	female
5987	uz_UZ	Yunus	male
5988	uz_UZ	Yusuf	male
5989	uz_UZ	Yusufa	female
5990	uz_UZ	Yusup	male
5991	uz_UZ	Yusupali	male
5992	uz_UZ	Zafar	male
5993	uz_UZ	Zafarjon	male
5994	uz_UZ	Zahit	male
5995	uz_UZ	Zamonoy	female
5996	uz_UZ	Zanjabil	female
5997	uz_UZ	Zarafshon	female
5998	uz_UZ	Zari	female
5999	uz_UZ	Zarif	male
6000	uz_UZ	Zarifa	female
6001	uz_UZ	Zarigul	female
6002	uz_UZ	Zarina	female
6003	uz_UZ	Zarkor	male
6004	uz_UZ	Zarnigor	female
6005	uz_UZ	Zavqiddin	male
6006	uz_UZ	Zayniddin	male
6007	uz_UZ	Zaynulla	male
6008	uz_UZ	Zebiniso	female
6009	uz_UZ	Zebo	female
6010	uz_UZ	Zeboxon	female
6011	uz_UZ	Zebuniso	female
6012	uz_UZ	Zikir	male
6013	uz_UZ	Zikrilloh	male
6014	uz_UZ	Zilola	female
6015	uz_UZ	Ziynat	female
6016	uz_UZ	Ziyo	male
6017	uz_UZ	Ziyod	male
6018	uz_UZ	Ziyoda	female
6019	uz_UZ	Ziyodaxon	female
6020	uz_UZ	Ziyodulla	male
6021	uz_UZ	Ziyovuddin	male
6022	uz_UZ	Zohid	male
6023	uz_UZ	Zohida	female
6024	uz_UZ	Zohidjon	male
6025	uz_UZ	Zoir	male
6026	uz_UZ	Zokir	male
6027	uz_UZ	Zokirjon	male
6028	uz_UZ	Zomin	male
6029	uz_UZ	Zubayda	female
6030	uz_UZ	Zubayr	male
6031	uz_UZ	Zufar	male
6032	uz_UZ	Zuhra	female
6033	uz_UZ	Zulayho	female
6034	uz_UZ	Zulfiya	female
6035	uz_UZ	Zulfizar	female
6036	uz_UZ	Zumrad	female
6037	uz_UZ	Zunnura	female
6038	uz_UZ	Zurriyot	female
5506	uz_UZ	No'mon	male
\.


--
-- Data for Name: hair_colors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.hair_colors (id, locale_code, color_name) FROM stdin;
1	uz_UZ	Black
2	uz_UZ	Brown
3	uz_UZ	Blond
4	uz_UZ	White
5	kk_KZ	Black
6	kk_KZ	Brown
7	kk_KZ	Blond
8	kk_KZ	White
11	uz_UZ	Dark brown
12	uz_UZ	Light brown
14	uz_UZ	Red
15	uz_UZ	Gray
19	kk_KZ	Dark brown
20	kk_KZ	Light brown
22	kk_KZ	Red
23	kk_KZ	Gray
\.


--
-- Data for Name: last_names; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.last_names (id, locale_code, surname, gender) FROM stdin;
1	uz_UZ	Karimov	male
2	uz_UZ	Karimova	female
3	uz_UZ	Ismoilov	male
4	uz_UZ	Ismoilova	female
5	kk_KZ	Omarov	male
6	kk_KZ	Omarova	female
7	kk_KZ	Sarsenov	male
8	kk_KZ	Sarsenova	female
9	uz_UZ	Abbasov	male
10	uz_UZ	Abbasova	female
11	uz_UZ	Abdullayev	male
12	uz_UZ	Abdullayeva	female
13	uz_UZ	Abdurahimov	male
14	uz_UZ	Abdurahimova	female
15	uz_UZ	Abdurahmonov	male
16	uz_UZ	Abdurahmonova	female
17	uz_UZ	Abduvaliyev	male
18	uz_UZ	Abduvaliyeva	female
19	uz_UZ	Ahmedov	male
20	uz_UZ	Ahmedova	female
21	uz_UZ	Akbarov	male
22	uz_UZ	Akbarova	female
23	uz_UZ	Akhmedov	male
24	uz_UZ	Akhmedova	female
25	uz_UZ	Akramov	male
26	uz_UZ	Akramova	female
27	uz_UZ	Alimov	male
28	uz_UZ	Alimova	female
29	uz_UZ	Aliyev	male
30	uz_UZ	Aliyeva	female
31	uz_UZ	Allayorov	male
32	uz_UZ	Allayorova	female
33	uz_UZ	Amanov	male
34	uz_UZ	Amanova	female
35	uz_UZ	Aminov	male
36	uz_UZ	Aminova	female
37	uz_UZ	Anvarov	male
38	uz_UZ	Anvarova	female
39	uz_UZ	Aripov	male
40	uz_UZ	Aripova	female
41	uz_UZ	Asadov	male
42	uz_UZ	Asadova	female
43	uz_UZ	Askarov	male
44	uz_UZ	Askarova	female
45	uz_UZ	Aslanov	male
46	uz_UZ	Aslanova	female
47	uz_UZ	Atayev	male
48	uz_UZ	Atayeva	female
49	uz_UZ	Avazov	male
50	uz_UZ	Avazova	female
51	uz_UZ	Azizov	male
52	uz_UZ	Azizova	female
53	uz_UZ	Babayev	male
54	uz_UZ	Babayeva	female
55	uz_UZ	Bakirov	male
56	uz_UZ	Bakirova	female
57	uz_UZ	Baratov	male
58	uz_UZ	Baratova	female
59	uz_UZ	Bekmurodov	male
60	uz_UZ	Bekmurodova	female
61	uz_UZ	Beknazarov	male
62	uz_UZ	Beknazarova	female
63	uz_UZ	Berdiev	male
64	uz_UZ	Berdieva	female
65	uz_UZ	Boboyev	male
66	uz_UZ	Boboyeva	female
67	uz_UZ	Boltayev	male
68	uz_UZ	Boltayeva	female
69	uz_UZ	Burhonov	male
70	uz_UZ	Burhonova	female
71	uz_UZ	Davlatov	male
72	uz_UZ	Davlatova	female
73	uz_UZ	Davronov	male
74	uz_UZ	Davronova	female
75	uz_UZ	Djalilov	male
76	uz_UZ	Djalilova	female
77	uz_UZ	Djurayev	male
78	uz_UZ	Djurayeva	female
79	uz_UZ	Dustov	male
80	uz_UZ	Dustova	female
81	uz_UZ	Ergashev	male
82	uz_UZ	Ergasheva	female
83	uz_UZ	Ermatov	male
84	uz_UZ	Ermatova	female
85	uz_UZ	Eshonov	male
86	uz_UZ	Eshonova	female
87	uz_UZ	Fayziyev	male
88	uz_UZ	Fayziyeva	female
89	uz_UZ	Fazilov	male
90	uz_UZ	Fazilova	female
91	uz_UZ	Fozilov	male
92	uz_UZ	Fozilova	female
93	uz_UZ	Gafurov	male
94	uz_UZ	Gafurova	female
95	uz_UZ	Ganiyev	male
96	uz_UZ	Ganiyeva	female
97	uz_UZ	Gulomov	male
98	uz_UZ	Gulomova	female
99	uz_UZ	Hakimov	male
100	uz_UZ	Hakimova	female
101	uz_UZ	Hamidov	male
102	uz_UZ	Hamidova	female
103	uz_UZ	Hasanov	male
104	uz_UZ	Hasanova	female
105	uz_UZ	Haydarov	male
106	uz_UZ	Haydarova	female
107	uz_UZ	Hayitov	male
108	uz_UZ	Hayitova	female
109	uz_UZ	Hoshimov	male
110	uz_UZ	Hoshimova	female
111	uz_UZ	Ibragimov	male
112	uz_UZ	Ibragimova	female
113	uz_UZ	Ikramov	male
114	uz_UZ	Ikramova	female
115	uz_UZ	Ilhomov	male
116	uz_UZ	Ilhomova	female
117	uz_UZ	Imomov	male
118	uz_UZ	Imomova	female
119	uz_UZ	Inomov	male
120	uz_UZ	Inomova	female
121	uz_UZ	Isayev	male
122	uz_UZ	Isayeva	female
123	uz_UZ	Iskandarov	male
124	uz_UZ	Iskandarova	female
125	uz_UZ	Islomov	male
126	uz_UZ	Islomova	female
129	uz_UZ	Jalilov	male
130	uz_UZ	Jalilova	female
131	uz_UZ	Jamolov	male
132	uz_UZ	Jamolova	female
133	uz_UZ	Jo'rayev	male
134	uz_UZ	Jo'rayeva	female
135	uz_UZ	Jumayev	male
136	uz_UZ	Jumayeva	female
139	uz_UZ	Kamilov	male
140	uz_UZ	Kamilova	female
141	uz_UZ	Komilov	male
142	uz_UZ	Komilova	female
143	uz_UZ	Latipov	male
144	uz_UZ	Latipova	female
145	uz_UZ	Madaminov	male
146	uz_UZ	Madaminova	female
147	uz_UZ	Mahmudov	male
148	uz_UZ	Mahmudova	female
149	uz_UZ	Majidov	male
150	uz_UZ	Majidova	female
151	uz_UZ	Mamatov	male
152	uz_UZ	Mamatova	female
153	uz_UZ	Mamayev	male
154	uz_UZ	Mamayeva	female
155	uz_UZ	Mansurov	male
156	uz_UZ	Mansurova	female
157	uz_UZ	Matkarimov	male
158	uz_UZ	Matkarimova	female
159	uz_UZ	Mirzayev	male
160	uz_UZ	Mirzayeva	female
161	uz_UZ	Muminov	male
162	uz_UZ	Muminova	female
163	uz_UZ	Murodov	male
164	uz_UZ	Murodova	female
165	uz_UZ	Musayev	male
166	uz_UZ	Musayeva	female
167	uz_UZ	Mustafayev	male
168	uz_UZ	Mustafayeva	female
169	uz_UZ	Nabiyev	male
170	uz_UZ	Nabiyeva	female
171	uz_UZ	Nazarov	male
172	uz_UZ	Nazarova	female
173	uz_UZ	Nematov	male
174	uz_UZ	Nematova	female
175	uz_UZ	Nishonov	male
176	uz_UZ	Nishonova	female
177	uz_UZ	Niyazov	male
178	uz_UZ	Niyazova	female
179	uz_UZ	Nizamov	male
180	uz_UZ	Nizamova	female
181	uz_UZ	Nurmatov	male
182	uz_UZ	Nurmatova	female
183	uz_UZ	Nurmurodov	male
184	uz_UZ	Nurmurodova	female
185	uz_UZ	Olimov	male
186	uz_UZ	Olimova	female
187	uz_UZ	Oripov	male
188	uz_UZ	Oripova	female
189	uz_UZ	Otajonov	male
190	uz_UZ	Otajonova	female
191	uz_UZ	Otaboyev	male
192	uz_UZ	Otaboyeva	female
193	uz_UZ	Qodirov	male
194	uz_UZ	Qodirova	female
195	uz_UZ	Qosimov	male
196	uz_UZ	Qosimova	female
197	uz_UZ	Qurbanov	male
198	uz_UZ	Qurbanova	female
199	uz_UZ	Rahimov	male
200	uz_UZ	Rahimova	female
201	uz_UZ	Rahmonov	male
202	uz_UZ	Rahmonova	female
203	uz_UZ	Rajabov	male
204	uz_UZ	Rajabova	female
205	uz_UZ	Raufov	male
206	uz_UZ	Raufova	female
207	uz_UZ	Ravshanov	male
208	uz_UZ	Ravshanova	female
209	uz_UZ	Rasulov	male
210	uz_UZ	Rasulova	female
211	uz_UZ	Raxmatov	male
212	uz_UZ	Raxmatova	female
213	uz_UZ	Rustamov	male
214	uz_UZ	Rustamova	female
215	uz_UZ	Saidov	male
216	uz_UZ	Saidova	female
217	uz_UZ	Salimov	male
218	uz_UZ	Salimova	female
219	uz_UZ	Samadov	male
220	uz_UZ	Samadova	female
221	uz_UZ	Sattorov	male
222	uz_UZ	Sattorova	female
223	uz_UZ	Sharipov	male
224	uz_UZ	Sharipova	female
225	uz_UZ	Shamsiyev	male
226	uz_UZ	Shamsiyeva	female
227	uz_UZ	Shukurov	male
228	uz_UZ	Shukurova	female
229	uz_UZ	Sobirov	male
230	uz_UZ	Sobirova	female
231	uz_UZ	Sodiqov	male
232	uz_UZ	Sodiqova	female
233	uz_UZ	Soliyev	male
234	uz_UZ	Soliyeva	female
235	uz_UZ	Sultonov	male
236	uz_UZ	Sultonova	female
237	uz_UZ	Tadjiev	male
238	uz_UZ	Tadjieva	female
239	uz_UZ	Teshayev	male
240	uz_UZ	Teshayeva	female
241	uz_UZ	Tohirov	male
242	uz_UZ	Tohirova	female
243	uz_UZ	Tojiboyev	male
244	uz_UZ	Tojiboyeva	female
245	uz_UZ	Tolipov	male
246	uz_UZ	Tolipova	female
247	uz_UZ	Toshmatov	male
248	uz_UZ	Toshmatova	female
249	uz_UZ	To'xtayev	male
250	uz_UZ	To'xtayeva	female
251	uz_UZ	Turgunov	male
252	uz_UZ	Turgunova	female
253	uz_UZ	Umarov	male
254	uz_UZ	Umarova	female
255	uz_UZ	Usmonov	male
256	uz_UZ	Usmonova	female
257	uz_UZ	Ubaydullayev	male
258	uz_UZ	Ubaydullayeva	female
259	uz_UZ	Ulugov	male
260	uz_UZ	Ulugova	female
261	uz_UZ	Valiyev	male
262	uz_UZ	Valiyeva	female
263	uz_UZ	Xalilov	male
264	uz_UZ	Xalilova	female
265	uz_UZ	Xolmatov	male
266	uz_UZ	Xolmatova	female
267	uz_UZ	Xudoyberdiyev	male
268	uz_UZ	Xudoyberdiyeva	female
269	uz_UZ	Yoldoshev	male
270	uz_UZ	Yoldosheva	female
271	uz_UZ	Yunusov	male
272	uz_UZ	Yunusova	female
273	uz_UZ	Yusupov	male
274	uz_UZ	Yusupova	female
275	uz_UZ	Zafarov	male
276	uz_UZ	Zafarova	female
277	uz_UZ	Zokirov	male
278	uz_UZ	Zokirova	female
279	kk_KZ	Abayev	male
280	kk_KZ	Abayeva	female
281	kk_KZ	Abdrakhmanov	male
282	kk_KZ	Abdrakhmanova	female
283	kk_KZ	Abdullayev	male
284	kk_KZ	Abdullayeva	female
285	kk_KZ	Abilov	male
286	kk_KZ	Abilova	female
287	kk_KZ	Abishev	male
288	kk_KZ	Abisheva	female
289	kk_KZ	Adilov	male
290	kk_KZ	Adilova	female
291	kk_KZ	Aitbayev	male
292	kk_KZ	Aitbayeva	female
293	kk_KZ	Aitkaliyev	male
294	kk_KZ	Aitkaliyeva	female
295	kk_KZ	Aitzhanov	male
296	kk_KZ	Aitzhanova	female
297	kk_KZ	Akhmetov	male
298	kk_KZ	Akhmetova	female
299	kk_KZ	Akhmetzhanov	male
300	kk_KZ	Akhmetzhanova	female
301	kk_KZ	Akimov	male
302	kk_KZ	Akimova	female
303	kk_KZ	Alimov	male
304	kk_KZ	Alimova	female
305	kk_KZ	Alimbayev	male
306	kk_KZ	Alimbayeva	female
307	kk_KZ	Alipov	male
308	kk_KZ	Alipova	female
309	kk_KZ	Amanov	male
310	kk_KZ	Amanova	female
311	kk_KZ	Amangeldiyev	male
312	kk_KZ	Amangeldiyeva	female
313	kk_KZ	Amanzholov	male
314	kk_KZ	Amanzholova	female
315	kk_KZ	Amirbekov	male
316	kk_KZ	Amirbekova	female
317	kk_KZ	Amireyev	male
318	kk_KZ	Amireyeva	female
319	kk_KZ	Aripov	male
320	kk_KZ	Aripova	female
321	kk_KZ	Asanov	male
322	kk_KZ	Asanova	female
323	kk_KZ	Askarov	male
324	kk_KZ	Askarova	female
325	kk_KZ	Aslanov	male
326	kk_KZ	Aslanova	female
327	kk_KZ	Aubakirov	male
328	kk_KZ	Aubakirova	female
329	kk_KZ	Ayaganov	male
330	kk_KZ	Ayaganova	female
331	kk_KZ	Baibekov	male
332	kk_KZ	Baibekova	female
333	kk_KZ	Baibolov	male
334	kk_KZ	Baibolova	female
335	kk_KZ	Baibosynov	male
336	kk_KZ	Baibosynova	female
337	kk_KZ	Baigaliyev	male
338	kk_KZ	Baigaliyeva	female
339	kk_KZ	Baigazin	male
340	kk_KZ	Baigazina	female
341	kk_KZ	Baikenov	male
342	kk_KZ	Baikenova	female
343	kk_KZ	Baimagambetov	male
344	kk_KZ	Baimagambetova	female
345	kk_KZ	Baimukhanov	male
346	kk_KZ	Baimukhanova	female
347	kk_KZ	Baimuratov	male
348	kk_KZ	Baimuratova	female
349	kk_KZ	Baipakov	male
350	kk_KZ	Baipakova	female
351	kk_KZ	Baisalov	male
352	kk_KZ	Baisalova	female
353	kk_KZ	Baitasov	male
354	kk_KZ	Baitasova	female
355	kk_KZ	Baitursynov	male
356	kk_KZ	Baitursynova	female
357	kk_KZ	Bakirov	male
358	kk_KZ	Bakirova	female
359	kk_KZ	Beketov	male
360	kk_KZ	Beketova	female
361	kk_KZ	Bekmukhanov	male
362	kk_KZ	Bekmukhanova	female
363	kk_KZ	Beknazarov	male
364	kk_KZ	Beknazarova	female
365	kk_KZ	Bektemirov	male
366	kk_KZ	Bektemirova	female
367	kk_KZ	Bekzhanov	male
368	kk_KZ	Bekzhanova	female
369	kk_KZ	Berdaliyev	male
370	kk_KZ	Berdaliyeva	female
371	kk_KZ	Berdibayev	male
372	kk_KZ	Berdibayeva	female
373	kk_KZ	Berikbayev	male
374	kk_KZ	Berikbayeva	female
375	kk_KZ	Bisenov	male
376	kk_KZ	Bisenova	female
377	kk_KZ	Bolatov	male
378	kk_KZ	Bolatova	female
379	kk_KZ	Boranbayev	male
380	kk_KZ	Boranbayeva	female
381	kk_KZ	Burkitbayev	male
382	kk_KZ	Burkitbayeva	female
383	kk_KZ	Dalabayev	male
384	kk_KZ	Dalabayeva	female
385	kk_KZ	Dauletov	male
386	kk_KZ	Dauletova	female
387	kk_KZ	Dosayev	male
388	kk_KZ	Dosayeva	female
389	kk_KZ	Dosmukhamedov	male
390	kk_KZ	Dosmukhamedova	female
391	kk_KZ	Duisenov	male
392	kk_KZ	Duisenova	female
393	kk_KZ	Eraliyev	male
394	kk_KZ	Eraliyeva	female
395	kk_KZ	Ermekov	male
396	kk_KZ	Ermekova	female
397	kk_KZ	Esenov	male
398	kk_KZ	Esenova	female
399	kk_KZ	Esenbayev	male
400	kk_KZ	Esenbayeva	female
401	kk_KZ	Esengaliyev	male
402	kk_KZ	Esengaliyeva	female
403	kk_KZ	Gabdullin	male
404	kk_KZ	Gabdullina	female
405	kk_KZ	Gabitov	male
406	kk_KZ	Gabitova	female
407	kk_KZ	Ibragimov	male
408	kk_KZ	Ibragimova	female
409	kk_KZ	Ilyasov	male
410	kk_KZ	Ilyasova	female
411	kk_KZ	Isabekov	male
412	kk_KZ	Isabekova	female
413	kk_KZ	Isayev	male
414	kk_KZ	Isayeva	female
415	kk_KZ	Iskakov	male
416	kk_KZ	Iskakova	female
417	kk_KZ	Ismagulov	male
418	kk_KZ	Ismagulova	female
419	kk_KZ	Ismailov	male
420	kk_KZ	Ismailova	female
421	kk_KZ	Kabylov	male
422	kk_KZ	Kabylova	female
423	kk_KZ	Kairatov	male
424	kk_KZ	Kairatova	female
425	kk_KZ	Kaliev	male
426	kk_KZ	Kalieva	female
427	kk_KZ	Kalybayev	male
428	kk_KZ	Kalybayeva	female
429	kk_KZ	Kamalov	male
430	kk_KZ	Kamalova	female
431	kk_KZ	Kanatov	male
432	kk_KZ	Kanatova	female
433	kk_KZ	Karabayev	male
434	kk_KZ	Karabayeva	female
435	kk_KZ	Karimov	male
436	kk_KZ	Karimova	female
437	kk_KZ	Kassenov	male
438	kk_KZ	Kassenova	female
439	kk_KZ	Kassymov	male
440	kk_KZ	Kassymova	female
441	kk_KZ	Kemelov	male
442	kk_KZ	Kemelova	female
443	kk_KZ	Kenesov	male
444	kk_KZ	Kenesova	female
445	kk_KZ	Kenzhebayev	male
446	kk_KZ	Kenzhebayeva	female
447	kk_KZ	Kenzhegulov	male
448	kk_KZ	Kenzhegulova	female
449	kk_KZ	Kenzheyev	male
450	kk_KZ	Kenzheyeva	female
451	kk_KZ	Khassenov	male
452	kk_KZ	Khassenova	female
453	kk_KZ	Koishibayev	male
454	kk_KZ	Koishibayeva	female
455	kk_KZ	Konayev	male
456	kk_KZ	Konayeva	female
457	kk_KZ	Koshkarbayev	male
458	kk_KZ	Koshkarbayeva	female
459	kk_KZ	Kozhabayev	male
460	kk_KZ	Kozhabayeva	female
461	kk_KZ	Kozhakhmetov	male
462	kk_KZ	Kozhakhmetova	female
463	kk_KZ	Kozhamkulov	male
464	kk_KZ	Kozhamkulova	female
465	kk_KZ	Kurmanov	male
466	kk_KZ	Kurmanova	female
467	kk_KZ	Kurmanbayev	male
468	kk_KZ	Kurmanbayeva	female
469	kk_KZ	Kurmangaliyev	male
470	kk_KZ	Kurmangaliyeva	female
471	kk_KZ	Kusainov	male
472	kk_KZ	Kusainova	female
473	kk_KZ	Makhatov	male
474	kk_KZ	Makhatova	female
475	kk_KZ	Mambetov	male
476	kk_KZ	Mambetova	female
477	kk_KZ	Maratov	male
478	kk_KZ	Maratova	female
479	kk_KZ	Meirbekov	male
480	kk_KZ	Meirbekova	female
481	kk_KZ	Mukanov	male
482	kk_KZ	Mukanova	female
483	kk_KZ	Mukhamedov	male
484	kk_KZ	Mukhamedova	female
485	kk_KZ	Mukhanov	male
486	kk_KZ	Mukhanova	female
487	kk_KZ	Musabayev	male
488	kk_KZ	Musabayeva	female
489	kk_KZ	Musin	male
490	kk_KZ	Musina	female
491	kk_KZ	Mustafin	male
492	kk_KZ	Mustafina	female
493	kk_KZ	Nurgaliyev	male
494	kk_KZ	Nurgaliyeva	female
495	kk_KZ	Nurmagambetov	male
496	kk_KZ	Nurmagambetova	female
497	kk_KZ	Nurmakhanov	male
498	kk_KZ	Nurmakhanova	female
499	kk_KZ	Nurmukhamedov	male
500	kk_KZ	Nurmukhamedova	female
501	kk_KZ	Nurpeisov	male
502	kk_KZ	Nurpeisova	female
503	kk_KZ	Nurzhanov	male
504	kk_KZ	Nurzhanova	female
507	kk_KZ	Orazov	male
508	kk_KZ	Orazova	female
509	kk_KZ	Orazbayev	male
510	kk_KZ	Orazbayeva	female
511	kk_KZ	Ospanov	male
512	kk_KZ	Ospanova	female
513	kk_KZ	Rakhimov	male
514	kk_KZ	Rakhimova	female
515	kk_KZ	Ryskulov	male
516	kk_KZ	Ryskulova	female
517	kk_KZ	Saduakasov	male
518	kk_KZ	Saduakasova	female
519	kk_KZ	Sagadiyev	male
520	kk_KZ	Sagadiyeva	female
521	kk_KZ	Saginov	male
522	kk_KZ	Saginova	female
523	kk_KZ	Saparov	male
524	kk_KZ	Saparova	female
527	kk_KZ	Sarsenbayev	male
528	kk_KZ	Sarsenbayeva	female
529	kk_KZ	Satpayev	male
530	kk_KZ	Satpayeva	female
531	kk_KZ	Seidakhmetov	male
532	kk_KZ	Seidakhmetova	female
533	kk_KZ	Seisenov	male
534	kk_KZ	Seisenova	female
535	kk_KZ	Seitov	male
536	kk_KZ	Seitova	female
537	kk_KZ	Serikov	male
538	kk_KZ	Serikova	female
539	kk_KZ	Shakenov	male
540	kk_KZ	Shakenova	female
541	kk_KZ	Smagulov	male
542	kk_KZ	Smagulova	female
543	kk_KZ	Suleimenov	male
544	kk_KZ	Suleimenova	female
545	kk_KZ	Sultanov	male
546	kk_KZ	Sultanova	female
547	kk_KZ	Taimanov	male
548	kk_KZ	Taimanova	female
549	kk_KZ	Talgatov	male
550	kk_KZ	Talgatova	female
551	kk_KZ	Tashkenbayev	male
552	kk_KZ	Tashkenbayeva	female
553	kk_KZ	Temirbekov	male
554	kk_KZ	Temirbekova	female
555	kk_KZ	Tleubayev	male
556	kk_KZ	Tleubayeva	female
557	kk_KZ	Tleukhanov	male
558	kk_KZ	Tleukhanova	female
559	kk_KZ	Tokayev	male
560	kk_KZ	Tokayeva	female
561	kk_KZ	Tolegenov	male
562	kk_KZ	Tolegenova	female
563	kk_KZ	Tuleyev	male
564	kk_KZ	Tuleyeva	female
565	kk_KZ	Ualikhanov	male
566	kk_KZ	Ualikhanova	female
567	kk_KZ	Yermekov	male
568	kk_KZ	Yermekova	female
569	kk_KZ	Yessenov	male
570	kk_KZ	Yessenova	female
571	kk_KZ	Zhaksybekov	male
572	kk_KZ	Zhaksybekova	female
573	kk_KZ	Zhakupov	male
574	kk_KZ	Zhakupova	female
575	kk_KZ	Zhanabayev	male
576	kk_KZ	Zhanabayeva	female
577	kk_KZ	Zhanibekov	male
578	kk_KZ	Zhanibekova	female
579	kk_KZ	Zhumabayev	male
580	kk_KZ	Zhumabayeva	female
581	kk_KZ	Zhumadilov	male
582	kk_KZ	Zhumadilova	female
583	kk_KZ	Zhumagulov	male
584	kk_KZ	Zhumagulova	female
585	kk_KZ	Zhumakanov	male
586	kk_KZ	Zhumakanova	female
587	kk_KZ	Zhumatayev	male
588	kk_KZ	Zhumatayeva	female
589	kk_KZ	Zhunisov	male
590	kk_KZ	Zhunisova	female
\.


--
-- Data for Name: locales; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.locales (locale_code, locale_name, street_word, house_word, apartment_word) FROM stdin;
uz_UZ	Uzbekistan	ko'chasi	uy	xonadon
kk_KZ	Kazakhstan	koshesi	ui	pater
\.


--
-- Data for Name: phone_operators; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.phone_operators (id, locale_code, operator_code) FROM stdin;
1	kk_KZ	701
2	kk_KZ	702
3	kk_KZ	705
4	kk_KZ	707
5	kk_KZ	747
6	kk_KZ	771
7	kk_KZ	775
8	kk_KZ	777
9	uz_UZ	20
10	uz_UZ	33
11	uz_UZ	50
12	uz_UZ	77
13	uz_UZ	88
14	uz_UZ	90
15	uz_UZ	91
16	uz_UZ	93
17	uz_UZ	94
18	uz_UZ	95
19	uz_UZ	97
20	uz_UZ	98
21	uz_UZ	99
\.


--
-- Data for Name: phone_settings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.phone_settings (locale_code, country_code, operator_code) FROM stdin;
uz_UZ	998	90
kk_KZ	7	701
\.


--
-- Data for Name: street_names; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.street_names (id, locale_code, street_name) FROM stdin;
1	uz_UZ	Amir Temur
2	uz_UZ	Navoi
3	uz_UZ	Mustaqillik
4	kk_KZ	Abai
5	kk_KZ	Dostyk
6	kk_KZ	Beibitshilik
10	uz_UZ	Istiqlol
11	uz_UZ	Shodlik
12	uz_UZ	Do'stlik
13	uz_UZ	Tinchlik
14	uz_UZ	Bahor
15	uz_UZ	Gulzor
16	uz_UZ	Bog'bon
17	uz_UZ	Chinor
18	uz_UZ	Bunyodkor
19	uz_UZ	Yangi Hayot
20	uz_UZ	Yoshlik
21	uz_UZ	Zarafshon
22	uz_UZ	Samarqand
23	uz_UZ	Buxoro
24	uz_UZ	Farg'ona
25	uz_UZ	Andijon
26	uz_UZ	Namangan
27	uz_UZ	Bobur
28	uz_UZ	Beruniy
29	uz_UZ	Ibn Sino
30	uz_UZ	Ulug'bek
31	uz_UZ	Al-Xorazmiy
32	uz_UZ	Furqat
33	uz_UZ	Muqimiy
34	uz_UZ	Ogahiy
35	uz_UZ	Nodira
36	uz_UZ	Zulfiya
37	uz_UZ	Oybek
38	uz_UZ	G'afur G'ulom
39	uz_UZ	Abdulla Qodiriy
40	uz_UZ	Cho'lpon
41	uz_UZ	Fitrat
42	uz_UZ	Alpomish
43	uz_UZ	Afrosiyob
44	uz_UZ	Nurafshon
45	uz_UZ	Sohil
46	uz_UZ	Oltin Vodiy
47	uz_UZ	Guliston
48	uz_UZ	Ipak Yo'li
49	uz_UZ	Shahrisabz
50	uz_UZ	Qoratosh
51	uz_UZ	Qatortol
52	uz_UZ	Farhod
53	uz_UZ	Lutfiy
54	uz_UZ	Kamolon
55	uz_UZ	Chilonzor
56	uz_UZ	Yakkasaroy
60	kk_KZ	Tauelsizdik
61	kk_KZ	Respublika
62	kk_KZ	Saryarka
63	kk_KZ	Zhibek Zholy
64	kk_KZ	Kabanbai Batyr
65	kk_KZ	Bogenbai Batyr
66	kk_KZ	Abylai Khan
67	kk_KZ	Kenesary
68	kk_KZ	Korkyt Ata
69	kk_KZ	Al-Farabi
70	kk_KZ	Shokan Ualikhanov
71	kk_KZ	Ybyrai Altynsarin
72	kk_KZ	Mukhtar Auezov
73	kk_KZ	Zhambyl
74	kk_KZ	Saken Seifullin
75	kk_KZ	Ilyas Zhansugurov
76	kk_KZ	Sabit Mukanov
77	kk_KZ	Gabit Musirepov
78	kk_KZ	Kanysh Satpayev
79	kk_KZ	Dinmukhamed Konayev
80	kk_KZ	Bauyrzhan Momyshuly
81	kk_KZ	Aliya Moldagulova
82	kk_KZ	Manshuk Mametova
83	kk_KZ	Rakhymzhan Koshkarbayev
84	kk_KZ	Shakarim
85	kk_KZ	Magzhan Zhumabayev
86	kk_KZ	Akhmet Baitursynov
87	kk_KZ	Alikhan Bokeikhan
88	kk_KZ	Mirzhakyp Dulatov
89	kk_KZ	Turar Ryskulov
90	kk_KZ	Tole Bi
91	kk_KZ	Kazybek Bi
92	kk_KZ	Aiteke Bi
93	kk_KZ	Nauryz
94	kk_KZ	Zhasyl
95	kk_KZ	Samal
96	kk_KZ	Dala
97	kk_KZ	Arman
98	kk_KZ	Baiterek
99	kk_KZ	Akzhol
100	kk_KZ	Alatau
101	kk_KZ	Ertis
102	kk_KZ	Esil
103	kk_KZ	Zhaiyk
104	kk_KZ	Syrdariya
105	kk_KZ	Karatau
106	kk_KZ	Zhetysu
\.


--
-- Data for Name: titles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.titles (id, locale_code, title, gender) FROM stdin;
1	uz_UZ	Mr.	male
2	uz_UZ	Ms.	female
3	kk_KZ	Mr.	male
4	kk_KZ	Ms.	female
\.


--
-- Name: cities_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cities_id_seq', 86, true);


--
-- Name: email_domains_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.email_domains_id_seq', 50, true);


--
-- Name: first_names_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.first_names_id_seq', 6038, true);


--
-- Name: hair_colors_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.hair_colors_id_seq', 24, true);


--
-- Name: last_names_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.last_names_id_seq', 590, true);


--
-- Name: phone_operators_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.phone_operators_id_seq', 21, true);


--
-- Name: street_names_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.street_names_id_seq', 106, true);


--
-- Name: titles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.titles_id_seq', 8, true);


--
-- Name: cities cities_locale_code_city_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_locale_code_city_name_key UNIQUE (locale_code, city_name);


--
-- Name: cities cities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_pkey PRIMARY KEY (id);


--
-- Name: email_domains email_domains_locale_code_domain_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_domains
    ADD CONSTRAINT email_domains_locale_code_domain_name_key UNIQUE (locale_code, domain_name);


--
-- Name: email_domains email_domains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_domains
    ADD CONSTRAINT email_domains_pkey PRIMARY KEY (id);


--
-- Name: first_names first_names_locale_code_name_gender_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.first_names
    ADD CONSTRAINT first_names_locale_code_name_gender_key UNIQUE (locale_code, name, gender);


--
-- Name: first_names first_names_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.first_names
    ADD CONSTRAINT first_names_pkey PRIMARY KEY (id);


--
-- Name: hair_colors hair_colors_locale_code_color_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hair_colors
    ADD CONSTRAINT hair_colors_locale_code_color_name_key UNIQUE (locale_code, color_name);


--
-- Name: hair_colors hair_colors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hair_colors
    ADD CONSTRAINT hair_colors_pkey PRIMARY KEY (id);


--
-- Name: last_names last_names_locale_code_surname_gender_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.last_names
    ADD CONSTRAINT last_names_locale_code_surname_gender_key UNIQUE (locale_code, surname, gender);


--
-- Name: last_names last_names_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.last_names
    ADD CONSTRAINT last_names_pkey PRIMARY KEY (id);


--
-- Name: locales locales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locales
    ADD CONSTRAINT locales_pkey PRIMARY KEY (locale_code);


--
-- Name: phone_operators phone_operators_locale_code_operator_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phone_operators
    ADD CONSTRAINT phone_operators_locale_code_operator_code_key UNIQUE (locale_code, operator_code);


--
-- Name: phone_operators phone_operators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phone_operators
    ADD CONSTRAINT phone_operators_pkey PRIMARY KEY (id);


--
-- Name: phone_settings phone_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phone_settings
    ADD CONSTRAINT phone_settings_pkey PRIMARY KEY (locale_code);


--
-- Name: street_names street_names_locale_code_street_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.street_names
    ADD CONSTRAINT street_names_locale_code_street_name_key UNIQUE (locale_code, street_name);


--
-- Name: street_names street_names_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.street_names
    ADD CONSTRAINT street_names_pkey PRIMARY KEY (id);


--
-- Name: titles titles_locale_code_title_gender_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.titles
    ADD CONSTRAINT titles_locale_code_title_gender_key UNIQUE (locale_code, title, gender);


--
-- Name: titles titles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.titles
    ADD CONSTRAINT titles_pkey PRIMARY KEY (id);


--
-- Name: cities cities_locale_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_locale_code_fkey FOREIGN KEY (locale_code) REFERENCES public.locales(locale_code);


--
-- Name: email_domains email_domains_locale_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_domains
    ADD CONSTRAINT email_domains_locale_code_fkey FOREIGN KEY (locale_code) REFERENCES public.locales(locale_code);


--
-- Name: first_names first_names_locale_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.first_names
    ADD CONSTRAINT first_names_locale_code_fkey FOREIGN KEY (locale_code) REFERENCES public.locales(locale_code);


--
-- Name: hair_colors hair_colors_locale_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hair_colors
    ADD CONSTRAINT hair_colors_locale_code_fkey FOREIGN KEY (locale_code) REFERENCES public.locales(locale_code);


--
-- Name: last_names last_names_locale_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.last_names
    ADD CONSTRAINT last_names_locale_code_fkey FOREIGN KEY (locale_code) REFERENCES public.locales(locale_code);


--
-- Name: phone_operators phone_operators_locale_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phone_operators
    ADD CONSTRAINT phone_operators_locale_code_fkey FOREIGN KEY (locale_code) REFERENCES public.locales(locale_code);


--
-- Name: phone_settings phone_settings_locale_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phone_settings
    ADD CONSTRAINT phone_settings_locale_code_fkey FOREIGN KEY (locale_code) REFERENCES public.locales(locale_code);


--
-- Name: street_names street_names_locale_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.street_names
    ADD CONSTRAINT street_names_locale_code_fkey FOREIGN KEY (locale_code) REFERENCES public.locales(locale_code);


--
-- Name: titles titles_locale_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.titles
    ADD CONSTRAINT titles_locale_code_fkey FOREIGN KEY (locale_code) REFERENCES public.locales(locale_code);


--
-- PostgreSQL database dump complete
--

\unrestrict ZLQL3as6BKuPjhp9dk2qQn0nZd8XuJbtkcPOCwAVCuYtjrIrZ1jxt1YogAjt8Xq

