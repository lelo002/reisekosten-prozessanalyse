-- Tabellen anlegen
create table cases (
  case_id text primary key,
  amount numeric,
  budget_number text
);
create table event_log (
  case_id text references cases(case_id),
  event_nr int,
  activity text,
  event_time timestamptz,
  resource text,
  role text,
  primary key (case_id, event_nr)
);
alter table cases enable row level security;
alter table event_log enable row level security;

-- A.1: Wie läuft der Prozess ab?
with v as (
  select case_id, string_agg(activity, ' > ' order by event_nr) as variante
  from event_log group by case_id
)
select variante, count(*) as anzahl,
       round(100.0 * count(*) / 10500, 1) as prozent
from v group by variante order by anzahl desc limit 5;

-- A.2: Wie läuft der Prozess ab? (genutzt)

with v as (
  select case_id,
         array_agg(
           case activity
             when 'Declaration SUBMITTED by EMPLOYEE'        then 'Einreichung'
             when 'Declaration APPROVED by ADMINISTRATION'   then 'Verwaltung'
             when 'Declaration APPROVED by BUDGET OWNER'     then 'Budget'
             when 'Declaration FINAL_APPROVED by SUPERVISOR' then 'Vorgesetzte'
             when 'Request Payment'                          then 'Anforderung'
             when 'Payment Handled'                          then 'Zahlung'
             else activity
           end
           order by event_nr
         ) as ablauf
  from event_log
  group by case_id
)
select ablauf[1] as s1,
       ablauf[2] as s2,
       ablauf[3] as s3,
       ablauf[4] as s4,
       ablauf[5] as s5,
       ablauf[6] as s6,
       count(*) as anzahl,
       round(100.0 * count(*) / 10500, 1) as prozent
from v
group by ablauf
order by anzahl desc
limit 3;

-- B: Wo wird gewartet?
with s as (
  select activity, event_time,
         lag(activity)   over (partition by case_id order by event_nr) as vorher,
         lag(event_time) over (partition by case_id order by event_nr) as zeit_vorher
  from event_log
)
select vorher, activity, count(*) as anzahl,
       round((percentile_cont(0.5) within group (
         order by extract(epoch from event_time - zeit_vorher) / 86400
       ))::numeric, 1) as median_tage
from s where vorher is not null
group by vorher, activity
having count(*) >= 100
order by median_tage desc limit 5;

-- C: Wie hängen Ablehnungen mit der Dauer zusammen?
with f as (
  select case_id,
         bool_or(activity like '%REJECTED%') as abgelehnt,
         min(event_time) as start,
         max(event_time) filter (where activity = 'Payment Handled') as bezahlt
  from event_log group by case_id
)
select abgelehnt, count(*) as bezahlte_antraege,
       round((percentile_cont(0.5) within group (
         order by extract(epoch from bezahlt - start) / 86400
       ))::numeric, 1) as median_tage
from f where bezahlt is not null
group by abgelehnt;