#sql/mart.f_customer_retention.sql

-- Откорректировано:
-- Удаляем ранее рассчитанные данные за неделю с УЧЕТОМ ГОДА.
DELETE FROM mart.f_customer_retention
WHERE period_id = (
    SELECT
        year_actual * 100 + week_of_year
    FROM mart.d_calendar
    WHERE date_actual = '{{ ds }}'::DATE
);

-- Собираем заказы за нужную неделю и ГОД.
WITH customers AS (
    SELECT
        f_sales.*,
        d_calendar.week_of_year,
        d_calendar.year_actual
    FROM mart.f_sales
    JOIN mart.d_calendar
        ON f_sales.date_id = d_calendar.date_id
    WHERE week_of_year = (
        SELECT week_of_year
        FROM mart.d_calendar
        WHERE date_actual = '{{ ds }}'::DATE
    )
    AND year_actual = (
        SELECT year_actual
        FROM mart.d_calendar
        WHERE date_actual = '{{ ds }}'::DATE
    )
),

-- Определяем новых клиентов: только один отгруженный заказ за неделю.
new_customers AS (
    SELECT customer_id
    FROM customers
    WHERE status = 'shipped'
    GROUP BY customer_id
    HAVING COUNT(*) = 1
),

-- Определяем вернувшихся клиентов: более одного отгруженного заказа за неделю.
returning_customers AS (
    SELECT customer_id
    FROM customers
    WHERE status = 'shipped'
    GROUP BY customer_id
    HAVING COUNT(*) > 1
),

-- Определяем клиентов, оформивших возврат за неделю.
refunded_customers AS (
    SELECT customer_id
    FROM customers
    WHERE status = 'refunded'
    GROUP BY customer_id
)

-- Записываем рассчитанные показатели в витрину удержания клиентов.
INSERT INTO mart.f_customer_retention (
    new_customers_count,
    new_customers_revenue,
    returning_customers_count,
    returning_customers_revenue,
    refunded_customer_count,
    customers_refunded,
    period_id,
    period_name,
    item_id
)
SELECT
    COALESCE(new_customers.customers, 0) AS new_customers_count,
    COALESCE(new_customers.revenue, 0) AS new_customers_revenue,

    COALESCE(returning_customers.customers, 0) AS returning_customers_count,
    COALESCE(returning_customers.revenue, 0) AS returning_customers_revenue,

    COALESCE(refunded_customers.customers, 0) AS refunded_customer_count,

    -- Считаем количество возвратов, а не сумму возвращённых денег.
    -- В исходном запросе здесь использовалась сумма payment_amount.
    COALESCE(refunded_customers.refunded, 0) AS customers_refunded,

    COALESCE(
        new_customers.year_actual,
        returning_customers.year_actual,
        refunded_customers.year_actual
    ) * 100
    +
    COALESCE(
        new_customers.week_of_year,
        returning_customers.week_of_year,
        refunded_customers.week_of_year
    ) AS period_id,

    -- Изменено с 'week' на 'weekly' согласно схеме витрины.
    'weekly' AS period_name,

    COALESCE(
        new_customers.item_id,
        returning_customers.item_id,
        refunded_customers.item_id
    ) AS item_id

FROM (
    SELECT
        year_actual,
        week_of_year,
        item_id,
        SUM(payment_amount) AS revenue,
        COUNT(DISTINCT customer_id) AS customers
    FROM customers
    WHERE status = 'shipped'
      AND customer_id IN (SELECT customer_id FROM new_customers)
    GROUP BY year_actual, week_of_year, item_id
) AS new_customers

FULL JOIN (
    SELECT
        year_actual,
        week_of_year,
        item_id,
        SUM(payment_amount) AS revenue,
        COUNT(DISTINCT customer_id) AS customers
    FROM customers
    WHERE status = 'shipped'
      AND customer_id IN (SELECT customer_id FROM returning_customers)
    GROUP BY year_actual, week_of_year, item_id
) AS returning_customers
    ON new_customers.year_actual = returning_customers.year_actual
    AND new_customers.week_of_year = returning_customers.week_of_year
    AND new_customers.item_id = returning_customers.item_id

FULL JOIN (
    SELECT
        year_actual,
        week_of_year,
        item_id,
        COUNT(*) AS refunded,
        COUNT(DISTINCT customer_id) AS customers
    FROM customers
    WHERE status = 'refunded'
      AND customer_id IN (SELECT customer_id FROM refunded_customers)
    GROUP BY year_actual, week_of_year, item_id
) AS refunded_customers

    -- Исправлено условие соединения: учитываем ключи обеих предыдущих выборок.
    ON COALESCE(new_customers.year_actual, returning_customers.year_actual)
          = refunded_customers.year_actual
    AND COALESCE(new_customers.week_of_year, returning_customers.week_of_year)
          = refunded_customers.week_of_year
    AND COALESCE(new_customers.item_id, returning_customers.item_id)
          = refunded_customers.item_id;
