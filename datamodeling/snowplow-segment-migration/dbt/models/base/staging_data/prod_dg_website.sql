-- This model is only used for development runs to speed up testing.
SELECT * FROM {{ source('production_desiring_god_website', 'PAGES') }} LIMIT 10