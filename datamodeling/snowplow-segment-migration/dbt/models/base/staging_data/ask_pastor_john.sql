-- This model is only used for development runs to speed up testing.
SELECT * FROM {{ source('ask_pastor_john', 'TRACKS') }} LIMIT 10