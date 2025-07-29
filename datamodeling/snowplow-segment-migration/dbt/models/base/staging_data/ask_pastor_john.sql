-- This model is only used for development runs to speed up testing.
SELECT * FROM {{ source('ask_pastor_john', 'tracks') }} LIMIT 10