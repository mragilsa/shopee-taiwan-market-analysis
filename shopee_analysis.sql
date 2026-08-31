-- TABLE OF CONTENTS:
-- 0. LAYER L0: RAW INGESTION (Line 8)
-- 1. LAYER L1: DIMENSION TABLES (Line 22)
-- 2. LAYER L2: FACT TABLES (Line 83)
-- 3. LAYER L3: PRESENTATION VIEWS (Line 126)
-- 4. LAYER L4: KPI QUERIES (Line 294)

-- L0 — RAW INGESTION
CREATE OR REPLACE TABLE raw_shopee AS
SELECT
    *
FROM
    read_csv_auto('data/shopee_products_clean.csv', HEADER = TRUE);

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT itemId) AS unique_products,
    COUNT(DISTINCT shopId) AS unique_shops
FROM
    raw_shopee;

-- L1 - DIMENSION TABLES

-- L1A - DIMENSION: SHOP
CREATE OR REPLACE TABLE dim_shop AS
SELECT DISTINCT ON (shopId)
    shopId,
    shopName,
    COALESCE(shopDetailedLocation, shopLocation) AS shop_location,
    shopCreatedAt,
    CAST(shopRating        AS DOUBLE)  AS shop_rating,
    CAST(shopResponseRate  AS DOUBLE)  AS shop_response_rate,
    CAST(shopResponseTime  AS BIGINT)  AS shop_response_time,
    CAST(shopFollowerCount AS BIGINT)  AS shop_follower_count,
    CAST(shopItemCount     AS BIGINT)  AS shop_item_count,
    CAST(shopRatingGood    AS BIGINT)  AS shop_rating_good,
    CAST(shopRatingNormal  AS BIGINT)  AS shop_rating_normal,
    CAST(shopRatingBad     AS BIGINT)  AS shop_rating_bad,
    CAST(isOfficialShop    AS BOOLEAN) AS is_official_shop,
    CAST(isShopeeVerified  AS BOOLEAN) AS is_shopee_verified
FROM raw_shopee
WHERE shopId IS NOT NULL
ORDER BY shopId, shopFollowerCount DESC NULLS LAST;

SELECT * FROM dim_shop LIMIT 100;

SELECT
    COUNT(*) AS total_shops,
    SUM(CASE WHEN is_official_shop THEN 1 ELSE 0 END) AS official_shops,
    ROUND(AVG(shop_rating), 3) AS avg_shop_rating,
    ROUND(AVG(shop_response_rate), 3) AS avg_response_rate
FROM dim_shop;

-- L1B - DIMENSION: PRODUCT
CREATE OR REPLACE TABLE dim_product AS
SELECT DISTINCT ON (itemId)
    itemId,
    shopId,
    title,
    brand,
    CAST(catId         AS BIGINT)   AS cat_id,
    CAST(condition     AS INTEGER)  AS condition,
    status,
    CAST(isAdult       AS BOOLEAN)  AS is_adult,
    CAST(isPreOrder    AS BOOLEAN)  AS is_pre_order,
    CAST(estimatedDays AS INTEGER)  AS estimated_days,
    CAST(modelsCount   AS INTEGER)  AS models_count,
    createdAt
FROM raw_shopee
WHERE itemId IS NOT NULL
ORDER BY itemId;

SELECT * FROM dim_product LIMIT 100;

SELECT
    COUNT(*) AS total_products,
    COUNT(DISTINCT cat_id) AS unique_categories,
    COUNT(DISTINCT brand) AS unique_brands,
    SUM(CASE WHEN status = 'normal' THEN 1 ELSE 0 END) AS active_products,
    SUM(CASE WHEN brand = 'Unknown' THEN 1 ELSE 0 END) AS unknown_brands
FROM dim_product;

-- L2 - FACT TABLE: PRODUCT LISTING
CREATE OR REPLACE TABLE fact_product_listing AS
SELECT
    itemId,
    shopId,

    CAST(priceMin AS DOUBLE) AS price_min_twd,
    CAST(priceMax AS DOUBLE) AS price_max_twd,
    ROUND((CAST(priceMin AS DOUBLE) + CAST(priceMax AS DOUBLE)) / 2.0, 2) AS price_mid_twd,

    COALESCE(CAST(discount AS DOUBLE), 0) AS discount_pct,

    COALESCE(CAST(shippingFeeMin AS DOUBLE), 0) AS shipping_fee_min_twd,
    CAST(isFreeShipping          AS BOOLEAN)    AS is_free_shipping,
    CAST(isServiceByShopee       AS BOOLEAN)    AS is_service_by_shopee,

    COALESCE(CAST(ratingAvg    AS DOUBLE), 0) AS rating_avg,
    COALESCE(CAST(ratingCount  AS BIGINT), 0) AS rating_count,
    COALESCE(CAST(commentCount AS BIGINT), 0) AS comment_count,
    COALESCE(CAST(likedCount   AS BIGINT), 0) AS liked_count,

    COALESCE(CAST(modelsCount AS INTEGER), 1) AS models_count,

    CAST(isAdult        AS BOOLEAN) AS is_adult,
    CAST(isPreOrder     AS BOOLEAN) AS is_pre_order,
    CAST(isOfficialShop AS BOOLEAN) AS is_official_shop,
    status,
    currency
FROM raw_shopee
WHERE itemId IS NOT NULL AND CAST(priceMin AS DOUBLE) > 0;

SELECT * FROM fact_product_listing LIMIT 100;

SELECT
    COUNT(*) AS total_records,
    COUNT(DISTINCT itemId) AS unique_products,
    ROUND(AVG(price_min_twd), 2) AS avg_price_twd,
    ROUND(MIN(price_min_twd), 2) AS min_price_twd,
    ROUND(MAX(price_min_twd), 2) AS max_price_twd,
    ROUND(AVG(discount_pct), 2) AS avg_discount_pct,
    SUM(CASE WHEN status = 'normal' THEN 1 ELSE 0 END) AS active_listings
FROM fact_product_listing;

-- L3 - PRESENTATION VIEWS

-- V1: Product Pricing View
CREATE OR REPLACE VIEW v_product_pricing AS
SELECT
    f.itemId,
    f.shopId,

    dp.title,
    dp.brand,
    dp.cat_id,
    dp.models_count,
    dp.is_pre_order,

    f.price_min_twd,
    f.price_max_twd,
    f.price_mid_twd,
    f.discount_pct,
    f.shipping_fee_min_twd,
    f.is_free_shipping,
    f.is_service_by_shopee,

    f.rating_avg,
    f.rating_count,
    f.comment_count,
    f.liked_count,

    f.is_official_shop,
    s.shopName AS shop_name,
    s.shop_location,
    s.shop_rating,
    s.shop_follower_count,
    s.shop_item_count,
    s.shop_response_rate,
    s.shop_response_time,
    s.is_shopee_verified,

    CASE
        WHEN f.price_mid_twd < 100   THEN '1. Under TWD 100'
        WHEN f.price_mid_twd < 500   THEN '2. TWD 100-499'
        WHEN f.price_mid_twd < 1000  THEN '3. TWD 500-999'
        WHEN f.price_mid_twd < 3000  THEN '4. TWD 1,000-2,999'
        WHEN f.price_mid_twd < 10000 THEN '5. TWD 3,000-9,999'
        ELSE                              '6. TWD 10,000+'
    END AS price_bucket,

    CASE
        WHEN f.discount_pct = 0  THEN '1. No Discount'
        WHEN f.discount_pct < 10 THEN '2. 1-9%'
        WHEN f.discount_pct < 20 THEN '3. 10-19%'
        WHEN f.discount_pct < 30 THEN '4. 20-29%'
        WHEN f.discount_pct < 50 THEN '5. 30-49%'
        ELSE                          '6. 50%+'
    END AS discount_band,

    CASE
        WHEN f.rating_avg >= 4.5 AND f.rating_count >= 50 THEN '1. Top Rated'
        WHEN f.rating_avg >= 4.0 AND f.rating_count >= 20 THEN '2. Well Rated'
        WHEN f.rating_count < 5                           THEN '3. Few Reviews'
        ELSE                                                   '4. Average'
    END AS rating_tier,

    CASE
        WHEN f.liked_count >= 1000 THEN '1. Viral (1K+)'
        WHEN f.liked_count >= 500  THEN '2. Popular (500-999)'
        WHEN f.liked_count >= 100  THEN '3. Growing (100-499)'
        ELSE                            '4. Low Engagement'
    END AS engagement_tier,

    CASE
        WHEN f.rating_count = 0  THEN '1. No Reviews'
        WHEN f.rating_count < 5  THEN '2. 1-4'
        WHEN f.rating_count < 20 THEN '3. 5-19'
        WHEN f.rating_count < 50 THEN '4. 20-49'
        ELSE                          '5. 50+'
    END AS review_bucket

FROM fact_product_listing f
LEFT JOIN dim_product dp ON f.itemId = dp.itemId
LEFT JOIN dim_shop s ON f.shopId = s.shopId
WHERE f.status = 'normal';

SELECT * FROM v_product_pricing LIMIT 100;

-- V2: Shop Perfomance View
CREATE OR REPLACE VIEW v_shop_performance AS
WITH shop_listing_metrics AS (
    SELECT
        shopId,
        COUNT(DISTINCT itemId) AS listing_count,
        ROUND(AVG(price_min_twd), 2) AS avg_price_twd,
        ROUND(AVG(discount_pct), 2) AS avg_discount_pct,
        ROUND(AVG(rating_avg), 2) AS avg_product_rating,
        SUM(rating_count) AS total_ratings,
        SUM(comment_count) AS total_comments,
        SUM(liked_count) AS total_likes,
        SUM(CASE WHEN is_free_shipping THEN 1 ELSE 0 END) AS free_shipping_count,
        SUM(CASE WHEN discount_pct > 0 THEN 1 ELSE 0 END) AS discounted_count,
        SUM(CASE WHEN is_service_by_shopee THEN 1 ELSE 0 END) AS shopee_fulfilled_count,
        ROUND(AVG(CAST(models_count AS DOUBLE)), 1) AS avg_models_count
    FROM fact_product_listing
    WHERE status = 'normal'
    GROUP BY shopId
)
SELECT
    s.shopId,
    s.shopName,
    s.shop_location,
    s.shop_rating,
    s.shop_response_rate,
    s.shop_response_time,
    s.shop_follower_count,
    s.shop_item_count,
    s.shop_rating_good,
    s.shop_rating_normal,
    s.shop_rating_bad,
    s.is_official_shop,
    s.is_shopee_verified,

    ROUND(
        s.shop_rating_good * 100.0
        / NULLIF(s.shop_rating_good + s.shop_rating_normal + s.shop_rating_bad, 0), 2
    ) AS positive_rating_pct,

    CASE
        WHEN s.shop_response_time <= 3600  THEN '1. Under 1 hour'
        WHEN s.shop_response_time <= 21600 THEN '2. 1-6 hours'
        WHEN s.shop_response_time <= 86400 THEN '3. 6-24 hours'
        ELSE                                    '4. Over 24 hours'
    END AS response_time_bucket,

    m.listing_count,
    m.avg_price_twd,
    m.avg_discount_pct,
    m.avg_product_rating,
    m.total_ratings,
    m.total_comments,
    m.total_likes,
    m.free_shipping_count,
    m.discounted_count,
    m.shopee_fulfilled_count,
    m.avg_models_count,

    ROUND(m.free_shipping_count * 100.0 / NULLIF(m.listing_count, 0), 2) AS free_shipping_rate,
    ROUND(m.discounted_count * 100.0 / NULLIF(m.listing_count, 0), 2) AS discount_rate,
    ROUND(m.shopee_fulfilled_count * 100.0 / NULLIF(m.listing_count, 0), 2) AS shopee_fulfilled_rate,

    (m.total_likes + m.total_comments + m.total_ratings) AS total_engagement_score,

    CASE
        WHEN s.is_official_shop                                      THEN '1. Official'
        WHEN s.shop_rating >= 4.8 AND s.shop_follower_count >= 1000  THEN '2. Power Seller'
        WHEN s.shop_rating >= 4.5                                    THEN '3. Established'
        ELSE                                                              '4. General'
    END AS shop_tier,

    CASE
        WHEN s.shop_follower_count >= 10000 THEN '1. 10,000+'
        WHEN s.shop_follower_count >= 1000  THEN '2. 1,000-9.999'
        WHEN s.shop_follower_count >= 100   THEN '3. 100-999'
        ELSE                                     '4. < 100'
    END AS follower_tier

FROM dim_shop s
LEFT JOIN shop_listing_metrics m on s.shopId = m.shopId;

SELECT * FROM v_shop_performance LIMIT 100;

-- L4 — KPI QUERIES

-- KPI 1: PRICING STRUCTURE

-- 1A. Price Bucket Distribution
SELECT
    price_bucket,
    COUNT(*)                                          AS listing_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_total,
    ROUND(AVG(price_min_twd), 2)                      AS avg_price_twd,
    ROUND(AVG(discount_pct), 2)                       AS avg_discount_pct,
    ROUND(AVG(rating_avg), 2)                         AS avg_rating,
    ROUND(AVG(liked_count), 1)                        AS avg_likes
FROM v_product_pricing
GROUP BY price_bucket
ORDER BY price_bucket;

-- 1B. Top 20 brands by average price
SELECT
    brand,
    COUNT(*)                     AS listing_count,
    ROUND(AVG(price_min_twd), 2) AS avg_price_twd,
    ROUND(MIN(price_min_twd), 2) AS min_price_twd,
    ROUND(MAX(price_min_twd), 2) AS max_price_twd,
    ROUND(AVG(rating_avg), 3)    AS avg_rating
FROM v_product_pricing
WHERE brand != 'Unknown'
GROUP BY brand
HAVING COUNT(*) >= 10
ORDER BY avg_price_twd DESC
LIMIT 20;

-- KPI 2: DISCOUNT DYNAMICS

-- 2A. Discount Band vs Engagement
WITH base AS (
    SELECT
        discount_band,
        ROUND(AVG(liked_count), 1) AS avg_likes
    FROM v_product_pricing
    GROUP BY discount_band
),
baseline AS (
    SELECT avg_likes AS no_discount_likes
    FROM base
    WHERE discount_band = '1. No Discount'
)
SELECT
    b.discount_band,
    b.avg_likes,
    ROUND((b.avg_likes - bl.no_discount_likes) / bl.no_discount_likes * 100, 1) AS vs_no_discount_pct
FROM base b
CROSS JOIN baseline bl
ORDER BY b.discount_band;

-- 2B. Discount vs engagement
SELECT
    ROUND(discount_pct / 5) * 5  AS discount_bin,
    COUNT(*)                     AS listing_count,
    ROUND(AVG(liked_count), 1)   AS avg_likes,
    ROUND(AVG(comment_count), 1) AS avg_comments,
    ROUND(AVG(rating_avg), 3)    AS avg_rating,
    ROUND(AVG(rating_count), 1)  AS avg_reviews
FROM v_product_pricing
WHERE discount_pct > 0
GROUP BY discount_bin
ORDER BY discount_bin;

-- KPI 3: SELLER PERFORMANCE TIERS

-- 3A. Shop tier summary
SELECT
    shop_tier,
    COUNT(*)                           AS shop_count,
    ROUND(AVG(shop_rating), 3)         AS avg_shop_rating,
    ROUND(AVG(shop_follower_count), 0) AS avg_followers,
    ROUND(AVG(listing_count), 1)       AS avg_listings,
    ROUND(AVG(avg_price_twd), 2)       AS avg_price_twd,
    ROUND(AVG(avg_discount_pct), 2)    AS avg_discount_pct,
    ROUND(AVG(free_shipping_rate), 2)  AS avg_free_shipping_rate,
    ROUND(AVG(shop_response_rate), 2)  AS avg_response_rate
FROM v_shop_performance
GROUP BY shop_tier
ORDER BY shop_tier;

-- 3B. Official vs Non-Official comparison
SELECT
    CASE WHEN is_official_shop THEN 'Official' ELSE 'Non-Official' END AS shop_type,
    COUNT(*)                           AS shop_count,
    ROUND(AVG(shop_rating), 3)         AS avg_shop_rating,
    ROUND(AVG(positive_rating_pct), 2) AS avg_positive_rating_pct,
    ROUND(AVG(shop_response_rate), 2)  AS avg_response_rate,
    ROUND(AVG(shop_follower_count), 0) AS avg_followers,
    ROUND(AVG(listing_count), 1)       AS avg_listings,
    ROUND(AVG(avg_price_twd), 2)       AS avg_price_twd,
    ROUND(AVG(avg_discount_pct), 2)    AS avg_discount_pct,
    ROUND(AVG(free_shipping_rate), 2)  AS avg_free_shipping_rate
FROM v_shop_performance
GROUP BY is_official_shop;

-- 3C. Response rate vs shop rating
SELECT
    ROUND(shop_response_rate / 10) * 10 AS response_rate_bucket,
    COUNT(*)                            AS shop_count,
    ROUND(AVG(shop_rating), 3)          AS avg_shop_rating,
    ROUND(AVG(positive_rating_pct), 2)  AS avg_positive_pct,
    ROUND(AVG(avg_product_rating), 3)   AS avg_product_rating
FROM v_shop_performance
WHERE shop_response_rate IS NOT NULL
GROUP BY response_rate_bucket
ORDER BY response_rate_bucket;

-- 3D. Top 20 shops by total engagement
SELECT
    shopName,
    shop_location,
    shop_tier,
    shop_rating,
    shop_follower_count,
    listing_count,
    total_likes,
    total_comments,
    total_ratings,
    total_engagement_score,
    avg_price_twd,
    avg_discount_pct,
    free_shipping_rate
FROM v_shop_performance
ORDER BY total_engagement_score DESC
LIMIT 10;

-- KPI 4: SHIPPING & FULFILLMENT

-- 4A. Free shipping vs engagement
SELECT
    CASE WHEN is_free_shipping THEN 'Free Shipping' ELSE 'Not Free Shipping' END AS shipping_type,
    COUNT(*)                     AS listing_count,
    ROUND(AVG(rating_avg), 3)    AS avg_rating,
    ROUND(AVG(liked_count), 1)   AS avg_likes,
    ROUND(AVG(comment_count), 1) AS avg_comments,
    ROUND(AVG(price_min_twd), 2) AS avg_price_twd,
    ROUND(AVG(discount_pct), 2)  AS avg_discount_pct
FROM v_product_pricing
GROUP BY is_free_shipping;

-- 4B. Free shipping adoption by shop tier
SELECT
    shop_tier,
    COUNT(*)                          AS shop_count,
    ROUND(AVG(free_shipping_rate), 2) AS avg_free_shipping_rate,
    ROUND(AVG(avg_price_twd), 2)      AS avg_price_twd,
    ROUND(AVG(avg_product_rating), 3) AS avg_product_rating
FROM v_shop_performance
GROUP BY shop_tier
ORDER BY shop_tier;

-- KPI 5: PRODUCT ENGAGEMENT & VIRALITY

-- 5A. Engagement tier breakdown
SELECT
    engagement_tier,
    COUNT(*)                     AS listing_count,
    ROUND(AVG(price_min_twd), 2) AS avg_price_twd,
    ROUND(AVG(discount_pct), 2)  AS avg_discount_pct,
    ROUND(AVG(rating_avg), 3)    AS avg_rating,
    ROUND(AVG(rating_count), 1)  AS avg_reviews,
    SUM(CASE WHEN is_free_shipping THEN 1 ELSE 0 END) AS free_shipping_count,
    ROUND(
        SUM(CASE WHEN is_free_shipping THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    ) AS free_shipping_rate
FROM v_product_pricing
GROUP BY engagement_tier
ORDER BY engagement_tier;

-- 5B. Review threshold effect
SELECT
    review_bucket,
    COUNT(*)                     AS listing_count,
    ROUND(AVG(liked_count), 1)   AS avg_likes,
    ROUND(AVG(comment_count), 1) AS avg_comments,
    ROUND(AVG(rating_avg), 3)    AS avg_rating,
    ROUND(AVG(price_min_twd), 2) AS avg_price_twd
FROM v_product_pricing
GROUP BY review_bucket
ORDER BY review_bucket;

SELECT
    shop_tier,
    COUNT(*) AS shop_count,
    SUM(total_likes) AS total_likes,
    SUM(listing_count) AS total_listings,
    ROUND(SUM(total_likes) * 1.0 / SUM(listing_count), 2) AS likes_per_listing
FROM v_shop_performance
GROUP BY shop_tier
ORDER BY shop_tier;

COPY (SELECT * FROM v_product_pricing)
  TO 'tableau/01_product_pricing.csv' (HEADER, DELIMITER ',');

COPY (SELECT * FROM v_shop_performance)
  TO 'tableau/02_shop_performance.csv' (HEADER, DELIMITER ',');