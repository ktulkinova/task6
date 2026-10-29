create table if not exists names (
    locale text not null,
    kind text not null,
    idx integer not null check (idx >= 0),
    value text not null,
    primary key (locale, kind, idx)
);

create table if not exists dict_size (
    locale text not null,
    kind text not null,
    n integer not null check (n > 0),
    primary key (locale, kind)
);
