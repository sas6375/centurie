-- Centurie : base du test en famille
-- À coller dans Supabase > SQL Editor > New query, puis « Run ». Une seule fois.
-- Principe : chacun voit ses propres pronos ; ceux des autres deviennent visibles
-- seulement après la clôture de la question (règle appliquée par la base elle-même).

-- 1. Questions et heures de clôture (heure de Paris = UTC+1)
create table if not exists public.questions (
  id int primary key,
  closes_at timestamptz not null
);
insert into public.questions (id, closes_at) values
  (1,  '2026-10-30 19:00+01'),
  (2,  '2026-10-29 13:00+01'),
  (3,  '2026-10-31 22:00+01'),
  (4,  '2026-10-30 10:00+01'),
  (5,  '2026-11-01 21:00+01'),
  (6,  '2026-11-01 21:00+01'),
  (7,  '2026-10-30 22:00+01'),
  (8,  '2026-10-31 22:00+01'),
  (9,  '2026-10-29 22:00+01'),
  (10, '2026-10-30 20:00+01'),
  (11, '2026-10-29 08:00+01'),
  (12, '2026-11-02 22:00+01'),
  (13, '2026-10-30 20:00+01'),
  (14, '2026-10-30 20:00+01'),
  (15, '2026-10-29 12:00+01'),
  (16, '2026-10-29 22:00+01')
on conflict (id) do update set closes_at = excluded.closes_at;

-- 2. Joueurs (3 initiales, une par appareil)
create table if not exists public.players (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  initials text not null unique check (initials ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now()
);

-- 3. Pronostics
create table if not exists public.predictions (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  question_id int not null references public.questions,
  option smallint not null check (option between 0 and 3),
  stake int not null check (stake in (50, 100, 250)),
  updated_at timestamptz not null default now(),
  primary key (user_id, question_id)
);

-- 4. Résultats (saisis par l'administrateur)
create table if not exists public.results (
  question_id int primary key references public.questions,
  outcome text not null check (outcome in ('0','1','2','3','x')),
  set_at timestamptz not null default now()
);

-- 5. Administrateurs
create table if not exists public.admins (
  user_id uuid primary key references auth.users on delete cascade
);

alter table public.questions   enable row level security;
alter table public.players     enable row level security;
alter table public.predictions enable row level security;
alter table public.results     enable row level security;
alter table public.admins      enable row level security;

-- Questions et résultats : lisibles par tous
create policy "questions lisibles" on public.questions for select using (true);
create policy "resultats lisibles" on public.results for select using (true);
create policy "resultats admin" on public.results for all
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));
create policy "admin se voit" on public.admins for select using (user_id = auth.uid());

-- Joueurs : initiales visibles par tous, chacun gère sa ligne
create policy "joueurs lisibles" on public.players for select using (true);
create policy "joueur cree sa ligne" on public.players for insert with check (user_id = auth.uid());
create policy "joueur modifie sa ligne" on public.players for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Pronostics : les miens toujours, ceux des autres seulement après la clôture
create policy "pronos visibles" on public.predictions for select using (
  user_id = auth.uid()
  or exists (select 1 from public.questions q where q.id = question_id and q.closes_at <= now())
);
create policy "prono avant cloture (ajout)" on public.predictions for insert with check (
  user_id = auth.uid()
  and exists (select 1 from public.questions q where q.id = question_id and q.closes_at > now())
);
create policy "prono avant cloture (modif)" on public.predictions for update
  using (user_id = auth.uid() and exists (select 1 from public.questions q where q.id = question_id and q.closes_at > now()))
  with check (user_id = auth.uid() and exists (select 1 from public.questions q where q.id = question_id and q.closes_at > now()));
create policy "prono avant cloture (retrait)" on public.predictions for delete using (
  user_id = auth.uid() and exists (select 1 from public.questions q where q.id = question_id and q.closes_at > now())
);

-- Budget : 1 000 jetons au total par joueur
create or replace function public.check_budget() returns trigger language plpgsql as $$
begin
  if (select coalesce(sum(stake), 0) from public.predictions
      where user_id = new.user_id and question_id <> new.question_id) + new.stake > 1000 then
    raise exception 'Budget de 1 000 jetons dépassé';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists predictions_budget on public.predictions;
create trigger predictions_budget before insert or update on public.predictions
  for each row execute function public.check_budget();

-- À lancer PLUS TARD, après avoir choisi tes initiales dans le jeu (remplace SAS si besoin) :
-- insert into public.admins (user_id) select user_id from public.players where initials = 'SAS';

-- 6. « Qui a joué » (façon Doodle) : expose seulement joueur + question, jamais la réponse ni la mise
create or replace function public.participation()
returns table (user_id uuid, question_id int)
language sql stable security definer set search_path = public
as $$ select p.user_id, p.question_id from public.predictions p $$;
revoke all on function public.participation() from public;
grant execute on function public.participation() to anon, authenticated;
