-- This model is only used for development runs to speed up testing.
SELECT * FROM {{ source('ruby_production_desiring_god_website', 'TRACKS') }} LIMIT 10