-- ============================================================
-- RR Prompt Library — Supabase schema, policies and views
-- Run this once in the Supabase SQL editor (Database > SQL).
-- ============================================================

-- ---------- TABLES ----------

create table if not exists public.prompts (
  id            uuid primary key default gen_random_uuid(),
  section       text not null check (char_length(section) between 1 and 100),
  workstreams   text[] not null default '{}',
  title         text not null check (char_length(title) between 2 and 300),
  use_when      text not null default '' check (char_length(use_when) <= 1000),
  system_prompt text not null check (char_length(system_prompt) between 10 and 15000),
  user_template text not null check (char_length(user_template) between 10 and 15000),
  tags          text[] not null default '{}',
  status        text not null default 'pending'
                 check (status in ('pending','approved','rejected')),
  author        text not null default 'anonymous' check (char_length(author) <= 100),
  created_at    timestamptz not null default now()
);

create table if not exists public.ratings (
  id         uuid primary key default gen_random_uuid(),
  prompt_id  uuid not null references public.prompts(id) on delete cascade,
  value      int  not null check (value between 1 and 5),
  created_at timestamptz not null default now()
);

create table if not exists public.feedback (
  id         uuid primary key default gen_random_uuid(),
  prompt_id  uuid not null references public.prompts(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists idx_ratings_prompt  on public.ratings(prompt_id);
create index if not exists idx_feedback_prompt on public.feedback(prompt_id);
create index if not exists idx_prompts_status  on public.prompts(status);

-- ---------- RATING STATS VIEW ----------
-- Aggregated so the app never has to download every individual vote.
create or replace view public.prompt_rating_stats as
  select prompt_id,
         round(avg(value)::numeric, 2) as avg,
         count(*)                      as cnt
  from public.ratings
  group by prompt_id;

-- ---------- ROW LEVEL SECURITY ----------
-- The anon key shipped in the static page is PUBLIC by design.
-- These policies are what actually protect the data.

alter table public.prompts  enable row level security;
alter table public.ratings  enable row level security;
alter table public.feedback enable row level security;

-- PROMPTS
-- Everyone may read only APPROVED prompts (pending/rejected stay hidden).
drop policy if exists "read approved prompts" on public.prompts;
create policy "read approved prompts"
  on public.prompts for select
  using (status = 'approved');

-- Anyone may submit a prompt, but ONLY as 'pending'. They cannot self-approve.
-- Array lengths also capped to prevent oversized payloads at the DB layer.
drop policy if exists "submit pending prompts" on public.prompts;
create policy "submit pending prompts"
  on public.prompts for insert
  with check (
    status = 'pending'
    AND (workstreams is null OR cardinality(workstreams) <= 21)
    AND (tags is null OR cardinality(tags) <= 20)
  );

-- No anon UPDATE or DELETE policies = those operations are denied.
-- Maintainers approve/reject via the Admin tab using the service role key.

-- RATINGS — anyone can read aggregates and add a 1–5 vote; no edits/deletes.
drop policy if exists "read ratings" on public.ratings;
create policy "read ratings" on public.ratings for select using (true);
drop policy if exists "add rating" on public.ratings;
create policy "add rating" on public.ratings for insert with check (value between 1 and 5);

-- FEEDBACK — anyone can read and add; no edits/deletes.
drop policy if exists "read feedback" on public.feedback;
create policy "read feedback" on public.feedback for select using (true);
drop policy if exists "add feedback" on public.feedback;
create policy "add feedback" on public.feedback for insert with check (char_length(body) between 1 and 2000);

-- Expose the view to the API roles.
grant select on public.prompt_rating_stats to anon, authenticated;

-- ============================================================
-- HARDENING: run this block against an EXISTING database to
-- add field-length constraints that were not present before.
-- Safe to run more than once — each uses IF NOT EXISTS logic.
-- ============================================================
do $$ begin
  alter table public.prompts add constraint prompts_section_len   check (char_length(section) between 1 and 100);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.prompts add constraint prompts_title_len     check (char_length(title) between 2 and 300);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.prompts add constraint prompts_use_when_len  check (char_length(use_when) <= 1000);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.prompts add constraint prompts_sys_len       check (char_length(system_prompt) between 10 and 15000);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.prompts add constraint prompts_usr_len       check (char_length(user_template) between 10 and 15000);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.prompts add constraint prompts_author_len    check (char_length(author) <= 100);
exception when duplicate_object then null; end $$;
