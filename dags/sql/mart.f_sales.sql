INSERT INTO mart.f_sales (
    date_id,
    item_id,
    customer_id,
    city_id,
    quantity,
    payment_amount,
    status,
    uniq_id
)
SELECT
    dc.date_id,
    uol.item_id,
    uol.customer_id,
    uol.city_id,
    uol.quantity,

    /* Прописываем условие для возврата: */
    CASE
        WHEN uol.status = 'refunded' THEN -uol.payment_amount
        ELSE uol.payment_amount
    END AS payment_amount,

    uol.status,
    uol.uniq_id

FROM staging.user_order_log AS uol

LEFT JOIN mart.d_calendar AS dc
    ON uol.date_time::DATE = dc.date_actual
WHERE uol.date_time::DATE = '{{ ds }}'

ON CONFLICT (uniq_id) DO NOTHING; -- блок для пропуска записи с uniq_id, для избежания дубликатов.