DROP TABLE IF EXISTS shipments_cleaned;

CREATE TABLE shipments_cleaned AS

WITH stats AS (
    SELECT 
        percentile_cont(0.25) WITHIN GROUP (ORDER BY freight_cost) AS q1,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY freight_cost) AS q3
    FROM shipments
    WHERE freight_cost > 0
),
bounds AS (
    SELECT 
        q1 - (1.5 * (q3 - q1)) AS lower_bound,
        q3 + (1.5 * (q3 - q1)) AS upper_bound
    FROM stats
),
cleaned_and_deduplicated AS (
    SELECT 
        s.shipment_id,

        -- Step 1: Standardize text
        initcap(trim(s.origin_warehouse)) AS origin_warehouse,
        COALESCE(initcap(trim(s.destination_city)), 'Unknown') AS destination_city,
        upper(trim(s.destination_state)) AS destination_state,
        initcap(trim(s.shipment_status)) AS shipment_status,
		initcap(trim(s.carrier)) AS carrier,
        s.ship_date,
		s.delivery_date,

        -- Step 4: weight_kg
        CASE 
            WHEN s.weight_kg <= 0 OR s.weight_kg IS NULL
			THEN (SELECT (ROUND(AVG(weight_kg))) FROM shipments WHERE weight_kg > 0)
            ELSE ABS(s.weight_kg)
        END AS weight_kg,

        -- Step 6: freight_cost — impute then cap
        CASE 
            WHEN s.freight_cost IS NULL
              OR s.freight_cost = 0 
			  	THEN (SELECT ROUND(AVG(freight_cost)) FROM shipments WHERE freight_cost > 0)
            WHEN s.freight_cost > b.upper_bound THEN b.upper_bound
            WHEN s.freight_cost < b.lower_bound THEN b.lower_bound
            ELSE s.freight_cost
        END AS freight_cost,

        -- Step 4: items_count
        CASE 
            WHEN s.items_count < 0 THEN ABS(s.items_count)
            WHEN s.items_count = 0
              OR s.items_count IS NULL THEN (SELECT ROUND(AVG(items_count)) FROM shipments WHERE items_count > 0)
            ELSE s.items_count
        END AS items_count,

        -- Step 2: damage_reported
        CASE 
            WHEN trim(s.damage_reported) = ''
              OR s.damage_reported = 'NULL'
              OR s.damage_reported IS NULL   THEN NULL
            ELSE initcap(trim(s.damage_reported))
        END AS damage_reported,

        -- Step 3: Deduplicate with normalized casing
        ROW_NUMBER() OVER (
            PARTITION BY 
                initcap(trim(s.origin_warehouse)),
                COALESCE(initcap(trim(s.destination_city)), 'Unknown'),
                initcap(trim(s.carrier)),
                s.ship_date,
                s.weight_kg,
                s.freight_cost
            ORDER BY s.shipment_id
        ) AS row_num

    FROM shipments s
    CROSS JOIN bounds b
)

SELECT 
    shipment_id,
    origin_warehouse,
    destination_city,
    destination_state,
    carrier,
    ship_date,
    delivery_date,
    weight_kg,
    freight_cost,
    shipment_status,
    items_count,
    damage_reported,
    (delivery_date - ship_date)  AS transit_days,
    CASE 
        WHEN delivery_date IS NULL
          OR ship_date IS NULL  THEN 'Missing date'
        WHEN delivery_date = ship_date THEN 'Same day delivery'
		WHEN (delivery_date - ship_date) <=0 THEN 'Invalid'
        ELSE 'Valid'
    END AS date_check

FROM cleaned_and_deduplicated
WHERE row_num = 1;
