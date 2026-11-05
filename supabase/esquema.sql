-- Rise of Ages: cuentas, puntos y niveles de las partidas con rango.
-- Pégalo completo en Supabase > SQL Editor y pulsa Run. Se puede volver a ejecutar.
-- Es el MISMO proyecto de Supabase que Zombie War (ecosistema Kodyn Games):
--   * kodyn_profiles = cuenta común (mismo login y mismo nombre en todos los juegos).
--   * roa_*          = todo lo de Rise of Ages. Sus puntos NO se mezclan con los de zm_*.
-- Antes: Authentication > Sign In / Providers > "Allow anonymous sign-ins" (ya activo si
-- Zombie War está configurado).
--
-- Seguridad: los jugadores solo leen. Los puntos los escribe únicamente el servidor del
-- juego con la clave de servicio (roa_apply_result), así nadie se los puede subir.

-- =====================================================================================
-- Común Kodyn (solo se crea si todavía no existe; Zombie War define lo demás)
-- =====================================================================================
create table if not exists public.kodyn_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default 'Jugador',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.kodyn_profiles enable row level security;
drop policy if exists "kodyn perfiles visibles" on public.kodyn_profiles;
create policy "kodyn perfiles visibles" on public.kodyn_profiles
  for select to anon, authenticated using (true);
revoke insert, update, delete on public.kodyn_profiles from anon, authenticated;

-- =====================================================================================
-- Rise of Ages
-- =====================================================================================
create table if not exists public.roa_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  points integer not null default 0 check (points >= 0),
  games integer not null default 0,
  wins integer not null default 0,
  losses integer not null default 0,
  abandons integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists roa_profiles_points_idx on public.roa_profiles (points desc);

create table if not exists public.roa_matches (
  id bigint generated always as identity primary key,
  mode text not null,                 -- '1v1', '2v2', '4v4'
  winner_team integer,                -- null = sin ganador (no cuenta)
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.roa_match_players (
  match_id bigint not null references public.roa_matches (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  team integer not null,
  civ text not null default '',
  won boolean not null,
  abandoned boolean not null default false,
  delta integer not null,
  points_after integer not null,
  primary key (match_id, user_id)
);
create index if not exists roa_match_players_user_idx on public.roa_match_players (user_id, match_id desc);

alter table public.roa_profiles enable row level security;
alter table public.roa_matches enable row level security;
alter table public.roa_match_players enable row level security;
drop policy if exists "roa perfiles visibles" on public.roa_profiles;
create policy "roa perfiles visibles" on public.roa_profiles for select to anon, authenticated using (true);
drop policy if exists "roa partidas visibles" on public.roa_matches;
create policy "roa partidas visibles" on public.roa_matches for select to anon, authenticated using (true);
drop policy if exists "roa jugadores visibles" on public.roa_match_players;
create policy "roa jugadores visibles" on public.roa_match_players for select to anon, authenticated using (true);
revoke insert, update, delete on public.roa_profiles, public.roa_matches, public.roa_match_players
  from anon, authenticated;

-- Nivel según puntos: cada 100 puntos un nivel (0-99 = nivel 1, 100-199 = nivel 2…).
create or replace function public.roa_level(p_points integer)
returns integer
language sql
immutable
as $fn$
  select 1 + greatest(coalesce(p_points, 0), 0) / 100;
$fn$;

-- ¿Esta cuenta ya jugó Zombie War? (para la recompensa del ecosistema, por definir).
create or replace function public.roa_played_zombie_war(p_user uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_found boolean := false;
begin
  if to_regclass('public.zm_profiles') is null then
    return false;
  end if;
  execute 'select exists (select 1 from public.zm_profiles where id = $1 and matches > 0)'
    into v_found using p_user;
  return coalesce(v_found, false);
end;
$fn$;

create or replace function public.roa_profile_json(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select jsonb_build_object(
    'id', r.id,
    'name', coalesce(k.name, 'Jugador'),
    'points', r.points,
    'level', public.roa_level(r.points),
    'games', r.games,
    'wins', r.wins,
    'losses', r.losses,
    'zombie_war', public.roa_played_zombie_war(r.id))
  from public.roa_profiles r
  left join public.kodyn_profiles k on k.id = r.id
  where r.id = p_user;
$fn$;

-- El jugador crea (si no existe) y lee su perfil. Si p_name viene, cambia su nombre común.
create or replace function public.roa_ensure_profile(p_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_name text := left(trim(coalesce(p_name, '')), 16);
begin
  if auth.uid() is null then
    raise exception 'Sin sesión';
  end if;
  insert into public.kodyn_profiles (id, name)
  values (auth.uid(), case when length(v_name) >= 2 then v_name else 'Jugador' end)
  on conflict (id) do nothing;
  if length(v_name) >= 2 then
    update public.kodyn_profiles set name = v_name, updated_at = now()
     where id = auth.uid() and name is distinct from v_name;
  end if;
  insert into public.roa_profiles (id) values (auth.uid()) on conflict (id) do nothing;
  return public.roa_profile_json(auth.uid());
end;
$fn$;

-- Solo el servidor: perfil de un jugador al entrar a la cola.
create or replace function public.roa_server_profile(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
  insert into public.kodyn_profiles (id) values (p_user) on conflict (id) do nothing;
  insert into public.roa_profiles (id) values (p_user) on conflict (id) do nothing;
  return public.roa_profile_json(p_user);
end;
$fn$;

-- Solo el servidor: guarda el resultado de una partida con rango y reparte puntos.
-- p_players: [{"user_id": uuid, "team": 1, "civ": "maya", "abandoned": false}, …]
-- Ganar: +20, más hasta ±10 según la diferencia de puntos con el equipo rival
-- (ganarle a alguien más fuerte da más). Perder: -15, más hasta ±8 al revés.
-- Abandonar cuenta como perder y además -5. Los puntos nunca bajan de 0.
create or replace function public.roa_apply_result(p_mode text, p_winner_team integer, p_players jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_match bigint;
  v_p jsonb;
  v_user uuid;
  v_team integer;
  v_won boolean;
  v_left boolean;
  v_mine numeric;
  v_rival numeric;
  v_diff numeric;
  v_delta integer;
  v_before integer;
  v_after integer;
  v_out jsonb := '[]'::jsonb;
begin
  if p_mode not in ('1v1', '2v2', '4v4') then
    raise exception 'Modo no válido';
  end if;
  if jsonb_typeof(p_players) <> 'array' or jsonb_array_length(p_players) < 2 then
    raise exception 'Faltan jugadores';
  end if;
  -- Puntos de cada jugador antes de la partida.
  for v_p in select * from jsonb_array_elements(p_players) loop
    insert into public.roa_profiles (id) values ((v_p->>'user_id')::uuid) on conflict (id) do nothing;
  end loop;
  insert into public.roa_matches (mode, winner_team, detail)
  values (p_mode, p_winner_team, jsonb_build_object('players', p_players))
  returning id into v_match;
  for v_p in select * from jsonb_array_elements(p_players) loop
    v_user := (v_p->>'user_id')::uuid;
    v_team := (v_p->>'team')::integer;
    v_left := coalesce((v_p->>'abandoned')::boolean, false);
    v_won := p_winner_team is not null and v_team = p_winner_team and not v_left;
    select coalesce(avg(r.points), 0) into v_mine
      from jsonb_array_elements(p_players) e join public.roa_profiles r on r.id = (e->>'user_id')::uuid
     where (e->>'team')::integer = v_team;
    select coalesce(avg(r.points), 0) into v_rival
      from jsonb_array_elements(p_players) e join public.roa_profiles r on r.id = (e->>'user_id')::uuid
     where (e->>'team')::integer <> v_team;
    v_diff := v_rival - v_mine;
    if p_winner_team is null then
      v_delta := 0;
    elsif v_won then
      v_delta := 20 + greatest(-10, least(10, round(v_diff / 20)))::integer;
    else
      v_delta := -(15 + greatest(-8, least(8, round(-v_diff / 20)))::integer) - case when v_left then 5 else 0 end;
    end if;
    -- Guardar el resultado de cada uno en una tabla aparte: los promedios de arriba
    -- deben usar los puntos de ANTES de la partida para todos.
    v_out := v_out || jsonb_build_object('user_id', v_user, 'team', v_team, 'civ', coalesce(v_p->>'civ', ''),
      'won', v_won, 'abandoned', v_left, 'delta', v_delta);
  end loop;
  for v_p in select * from jsonb_array_elements(v_out) loop
    v_user := (v_p->>'user_id')::uuid;
    select points into v_before from public.roa_profiles where id = v_user for update;
    v_after := greatest(0, v_before + (v_p->>'delta')::integer);
    update public.roa_profiles
       set points = v_after,
           games = games + 1,
           wins = wins + case when (v_p->>'won')::boolean then 1 else 0 end,
           losses = losses + case when (v_p->>'won')::boolean or p_winner_team is null then 0 else 1 end,
           abandons = abandons + case when (v_p->>'abandoned')::boolean then 1 else 0 end,
           updated_at = now()
     where id = v_user;
    insert into public.roa_match_players (match_id, user_id, team, civ, won, abandoned, delta, points_after)
    values (v_match, v_user, (v_p->>'team')::integer, v_p->>'civ', (v_p->>'won')::boolean,
            (v_p->>'abandoned')::boolean, v_after - v_before, v_after);
  end loop;
  return (
    select jsonb_agg(jsonb_build_object('user_id', mp.user_id, 'delta', mp.delta, 'points', mp.points_after,
                                        'level', public.roa_level(mp.points_after), 'won', mp.won))
      from public.roa_match_players mp where mp.match_id = v_match);
end;
$fn$;

-- Tabla de posiciones (la pueden leer todos).
create or replace function public.roa_leaderboard(p_limit integer default 50)
returns table (name text, points integer, level integer, wins integer, losses integer)
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(k.name, 'Jugador'), r.points, public.roa_level(r.points), r.wins, r.losses
    from public.roa_profiles r left join public.kodyn_profiles k on k.id = r.id
   where r.games > 0
   order by r.points desc, r.wins desc
   limit least(greatest(coalesce(p_limit, 50), 1), 200);
$fn$;

-- Permisos: el jugador solo usa roa_ensure_profile y roa_leaderboard.
revoke execute on function public.roa_server_profile(uuid) from public, anon, authenticated;
revoke execute on function public.roa_apply_result(text, integer, jsonb) from public, anon, authenticated;
revoke execute on function public.roa_profile_json(uuid) from public, anon, authenticated;
revoke execute on function public.roa_played_zombie_war(uuid) from public, anon, authenticated;
grant execute on function public.roa_server_profile(uuid) to service_role;
grant execute on function public.roa_apply_result(text, integer, jsonb) to service_role;
grant execute on function public.roa_ensure_profile(text) to authenticated;
grant execute on function public.roa_leaderboard(integer) to anon, authenticated;
