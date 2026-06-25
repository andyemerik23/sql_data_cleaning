-- Data cleaning
select * from shipments;

-- 1. Trim values & Standarize text
select 
	initcap(trim(origin_warehouse)) as origin_warehouse,
	initcap(trim(destination_city)) as destination_city,
	initcap(trim(shipment_status)) as shipment_status,
	Upper(trim(destination_state)) as destination_state,
	initcap(trim(carrier)) as carrier
from shipments;

-- 2. Null handling
SELECT 
	case 
		when damage_reported = 'NULL' then NULL
		ELSE initcap(trim(damage_reported))
	END as damage_reported,
	coalesce(destination_city, 'unknown') as destination_city,
	coalesce(delivery_date::TEXT, 'Not Yet Delivered') as delivery_date
from shipments;

-- 3. Remove duplicates
-- check first
with duplicate_check as (
	SELECT 
	  *,
	  ROW_NUMBER() OVER (
	    PARTITION BY 
	      origin_warehouse, 
	      destination_city, 
	      carrier, 
	      ship_date, 
	      CAST(weight_kg AS text), 
	      CAST(freight_cost AS text)
	    ORDER BY shipment_id
	  ) AS row_num
	FROM shipments
)

select 
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
	damage_reported
from duplicate_check
where row_num = 1;

-- 4. 0 and Negative values
select 
	shipment_id,
	case 
	when weight_kg <0 then abs(weight_kg)
	when weight_kg =0 OR weight_kg IS NULL then (SELECT(ROUND(AVG(weight_kg))) from shipments where weight_kg>0)
	else weight_kg
	end as weight_kg_cleaned,
	
	case 
	when items_count <0 then abs(items_count)
	when items_count =0 then (SELECT(ROUND(AVG(items_count))) from shipments where items_count>0)
	else items_count
	end as items_count_cleaned

from shipments;

-- 5. Validate date logic
with flagged_shipments as (
	SELECT 
		shipment_id,
		ship_date,
		delivery_date,
		(delivery_date-ship_date) as transit_days,
	
		CASE 
			when delivery_date IS NULL OR ship_date IS NULL then 'Missing date'
			when delivery_date < ship_date then 'Invalid'
			when delivery_date = ship_date then 'same day delivery'
			else 'valid'
		end as date_check
	from shipments
)
select * from flagged_shipments
where date_check = 'Invalid';

-- 6. Detect outliers with IQR
with stats as (
	select 
		percentile_cont(0.25) within group (order by freight_cost) as q1,
		percentile_cont(0.75) within group (order by freight_cost) as q3
	FROM shipments
	where freight_cost > 0
),
bounds as (
	SELECT 
        q1 - (1.5 * (q3 - q1)) AS lower_bound,
        q3 + (1.5 * (q3 - q1)) AS upper_bound
    FROM stats
)

SELECT 
    s.shipment_id,
    s.freight_cost AS original_cost,
    CASE 
		WHEN s.freight_cost is NULL or s.freight_cost = 0 THEN (SELECT(round(AVG(freight_cost))) FROM shipments WHERE freight_cost >0)
        WHEN s.freight_cost > b.upper_bound THEN b.upper_bound
        WHEN s.freight_cost < b.lower_bound THEN b.lower_bound
        ELSE s.freight_cost
    END AS cleaned_cost,
    CASE 
		WHEN s.freight_cost is NULL or s.freight_cost = 0 then 'imputed'
        WHEN s.freight_cost > b.upper_bound THEN 'upper outlier'
        WHEN s.freight_cost < b.lower_bound THEN 'lower outlier'
        ELSE 'normal'
    END AS outlier_status
FROM shipments s
CROSS JOIN bounds b;