drop function if exists get_session_user;
drop type if exists get_session_user_result;
drop procedure if exists destroy_session;
drop function if exists create_session;
drop type if exists create_session_result;
drop procedure if exists prune_sessions;
drop view if exists live_sessions;
drop trigger if exists limit_sessions_trigger on sessions;
drop function if exists limit_sessions;
drop table if exists sessions;
drop table if exists users;
drop function if exists session_max_age;
drop function if exists max_sessions;

create function max_sessions() returns integer language plpgsql immutable parallel safe as $$ begin
	return 4;
end; $$;

create function session_max_age() returns interval language plpgsql immutable parallel safe as $$ begin
	return '1 day'::interval;
end; $$;

create table users (
	id bigint not null,
	created_at timestamp with time zone not null default transaction_timestamp(),
	name citext not null,
	name_fetched_at timestamp with time zone not null default transaction_timestamp(),
	constraint user_pk primary key (id)
);

create table sessions (
	id uuid default gen_random_uuid(),
	anti_csrf uuid default gen_random_uuid(),
	created_at timestamp with time zone not null default transaction_timestamp(),
	user_id bigint not null,
	foreign key (user_id) references users(id),
	primary key (id)
);

create function limit_sessions() returns trigger language plpgsql as $$ begin
	delete from sessions
		where id in (select id from sessions
			where user_id = new.user_id
			order by created_at desc
			offset max_sessions());
	return new;
end; $$;

create trigger limit_sessions_trigger
	after insert
	on sessions
	for each row
	execute function limit_sessions();

create view live_sessions as
	select * from sessions
		where transaction_timestamp() < created_at + session_max_age();

create procedure prune_sessions() language plpgsql as $$ declare
begin
	delete from sessions
		where id not in (select id from live_sessions);
end; $$;

create type create_session_result as (
	new_session uuid,
	anti_csrf uuid
);
create function create_session(
	in i_user_id bigint,
	in i_user_name citext
) returns create_session_result language plpgsql as $$ declare
	res create_session_result;
begin
	insert into users (id, name)
		values (i_user_id, i_user_name)
		on conflict on constraint user_pk do update
			set name = i_user_name, name_fetched_at = transaction_timestamp()
			where users.id = i_user_id;
	insert into sessions (user_id)
		values (i_user_id)
		returning id into res.new_session;
	return res;
end; $$;

create procedure destroy_session(
	in i_id uuid
) language plpgsql as $$ begin
	delete from sessions
		where id = i_id;
end; $$;

create type get_session_user_result as (
	status text,
	user_id bigint,
	user_name text,
	anti_csrf uuid
);
create function get_session_user(
	in i_session_str text
) returns get_session_user_result language plpgsql as $$ declare
	i_session uuid;
	res get_session_user_result;
begin
	begin
		i_session = cast(i_session_str as uuid);
	exception
		when invalid_text_representation then
			res.status = 'bad_uuid';
			return res;
	end;
	select user_id, name, anti_csrf
		from sessions join users on sessions.user_id = users.id
		where sessions.id = i_session
		into res.user_id, res.user_name, res.anti_csrf;
	if res.user_id is null then
		res.status = 'not_found';
	else
		res.status = 'found';
	end if;
	return res;
end; $$;
