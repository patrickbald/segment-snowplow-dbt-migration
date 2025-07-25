with source as ( 
    select * from {{ source('segment', 'pages')}}
)

select
    anonymous_id as domain_userid,

from source

