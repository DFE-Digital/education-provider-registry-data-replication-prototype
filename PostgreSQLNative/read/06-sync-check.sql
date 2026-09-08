SELECT s.subname, s.subenabled, s.subslotname
FROM pg_subscription s
WHERE s.subdbid = (SELECT oid
    FROM pg_database
    WHERE datname = current_database())
AND s.subname = 'epr_real_subscription';

SELECT subname, pid, received_lsn, latest_end_lsn
FROM pg_stat_subscription
WHERE subname = 'epr_real_subscription';

SELECT r.srsubstate, count(*)
FROM pg_subscription_rel r
JOIN pg_subscription s ON s.oid = r.srsubid
WHERE s.subname = 'epr_real_subscription'
GROUP BY r.srsubstate;

DO $$
BEGIN
    IF (SELECT count(*)
        FROM pg_subscription_rel r
        JOIN pg_subscription s ON s.oid = r.srsubid
        WHERE s.subname = 'epr_real_subscription' AND r.srsubstate = 'r') <> 33
    OR EXISTS (SELECT 1
        FROM pg_subscription_rel r
        JOIN pg_subscription s ON s.oid = r.srsubid
        WHERE s.subname = 'epr_real_subscription' AND r.srsubstate <> 'r')
    THEN
        RAISE EXCEPTION 'Initial sync incomplete: require all 33 tables ready; retry this file';

    END IF;

END
$$;
