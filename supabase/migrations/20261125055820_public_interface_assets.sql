-- Immutable interface releases are published by a trusted operator.
-- Private community media remains in its owner-scoped bucket.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('mina-art', 'mina-art', true, 10000000,
        array['application/json', 'image/png', 'audio/wav', 'text/plain'])
on conflict (id) do nothing;
