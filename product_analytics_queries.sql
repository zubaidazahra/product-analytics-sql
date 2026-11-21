-- PROJECT 01 | Product Analytics for a fictional global EdTech app
-- Load the cleaned CSVs into tables with the same names:
-- users, events, subscriptions, support_tickets, campaigns.
-- SQL dialect: SQLite 3.x. Dates are ISO-8601 text.

-- Q1. Acquisition overview: which channels bring the most users?
SELECT acquisition_channel, COUNT(*) AS signups,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS signup_share_pct
FROM users
GROUP BY acquisition_channel
ORDER BY signups DESC;

-- Q2. Activation: what share of new users complete a lesson within 7 days?
WITH first_lesson AS (
  SELECT user_id, MIN(event_date) AS first_lesson_date
  FROM events WHERE event_type = 'lesson_completed'
  GROUP BY user_id
),
cohort AS (
  SELECT u.user_id, u.signup_date, f.first_lesson_date
  FROM users u LEFT JOIN first_lesson f ON u.user_id = f.user_id
)
SELECT COUNT(*) AS total_signups,
       SUM(CASE WHEN julianday(first_lesson_date)-julianday(signup_date)
                     BETWEEN 0 AND 7 THEN 1 ELSE 0 END) AS activated_users,
       ROUND(100.0 * SUM(CASE WHEN julianday(first_lesson_date)-julianday(signup_date)
                     BETWEEN 0 AND 7 THEN 1 ELSE 0 END)/COUNT(*),1) AS activation_rate_pct
FROM cohort;

-- Q3. Where does the learning funnel lose users?
WITH user_stages AS (
 SELECT user_id,
        MAX(CASE WHEN event_type='app_open' THEN 1 ELSE 0 END) AS has_opened,
        MAX(CASE WHEN event_type='lesson_started' THEN 1 ELSE 0 END) AS has_started,
        MAX(CASE WHEN event_type='lesson_completed' THEN 1 ELSE 0 END) AS has_completed,
        MAX(CASE WHEN event_type='project_submitted' THEN 1 ELSE 0 END) AS has_submitted
 FROM events
 GROUP BY user_id
),
funnel AS (
 SELECT
  SUM(has_opened) AS opened,
  SUM(CASE WHEN has_opened=1 AND has_started=1 THEN 1 ELSE 0 END) AS started,
  SUM(CASE WHEN has_opened=1 AND has_started=1 AND has_completed=1 THEN 1 ELSE 0 END) AS completed,
  SUM(CASE WHEN has_opened=1 AND has_started=1 AND has_completed=1 AND has_submitted=1 THEN 1 ELSE 0 END) AS submitted
 FROM user_stages
)
SELECT opened, started, completed, submitted,
       ROUND(100.0*started/NULLIF(opened,0),1) AS open_to_start_pct,
       ROUND(100.0*completed/NULLIF(started,0),1) AS start_to_complete_pct,
       ROUND(100.0*submitted/NULLIF(completed,0),1) AS complete_to_project_pct
FROM funnel;

-- Q4. Which acquisition channels produce the most valuable users?
WITH user_value AS (
 SELECT u.user_id, u.acquisition_channel,
        COALESCE(SUM(CASE WHEN s.status IN ('Active','Cancelled','Expired')
                          THEN s.price_usd ELSE 0 END),0) AS booked_revenue
 FROM users u LEFT JOIN subscriptions s ON u.user_id=s.user_id
 GROUP BY u.user_id,u.acquisition_channel
)
SELECT acquisition_channel, COUNT(*) AS users,
       ROUND(AVG(booked_revenue),2) AS revenue_per_acquired_user,
       ROUND(SUM(booked_revenue),2) AS booked_revenue
FROM user_value
GROUP BY acquisition_channel
ORDER BY revenue_per_acquired_user DESC;

-- Q5. What does month-1 retention look like by signup cohort?
WITH monthly_activity AS (
 SELECT DISTINCT user_id, strftime('%Y-%m',event_date) AS activity_month
 FROM events
),
cohorts AS (
 SELECT user_id, strftime('%Y-%m',signup_date) AS cohort_month FROM users
),
cohort_size AS (
 SELECT cohort_month, COUNT(*) AS users FROM cohorts GROUP BY cohort_month
),
retained AS (
 SELECT c.cohort_month, COUNT(DISTINCT c.user_id) AS retained_users
 FROM cohorts c JOIN monthly_activity a ON c.user_id=a.user_id
 WHERE a.activity_month = strftime('%Y-%m', date(c.cohort_month || '-01','+1 month'))
 GROUP BY c.cohort_month
)
SELECT s.cohort_month, s.users,
       COALESCE(r.retained_users,0) AS month1_active_users,
       ROUND(100.0*COALESCE(r.retained_users,0)/s.users,1) AS month1_retention_pct
FROM cohort_size s LEFT JOIN retained r USING(cohort_month)
ORDER BY s.cohort_month;

-- Q6. Are paid subscribers cancelling quickly?
SELECT plan_type, COUNT(*) AS subscriptions,
       SUM(CASE WHEN status='Cancelled' THEN 1 ELSE 0 END) AS cancelled,
       ROUND(100.0*SUM(CASE WHEN status='Cancelled' THEN 1 ELSE 0 END)/COUNT(*),1) AS cancellation_pct,
       ROUND(AVG(CASE WHEN cancel_date<>'' AND cancel_date IS NOT NULL
                      THEN julianday(cancel_date)-julianday(start_date) END),1) AS avg_days_to_cancel
FROM subscriptions
GROUP BY plan_type;

-- Q7. Which support issues take longest to resolve?
SELECT issue_category, COUNT(*) AS ticket_count,
       ROUND(AVG(resolution_hours),1) AS avg_resolution_hours,
       SUM(CASE WHEN ticket_status IN ('Open','Escalated') THEN 1 ELSE 0 END) AS unresolved
FROM support_tickets
GROUP BY issue_category
ORDER BY avg_resolution_hours DESC;

-- Q8. Campaign efficiency: which campaigns have the lowest cost per signup?
SELECT campaign_name, channel, spend_usd, attributed_signups,
       ROUND(1.0*spend_usd/NULLIF(attributed_signups,0),2) AS cost_per_signup_usd
FROM campaigns
ORDER BY cost_per_signup_usd;
