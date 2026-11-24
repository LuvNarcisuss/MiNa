create policy night_journal_portrait_delivery on storage.objects for insert to authenticated with check (
    (select auth.uid()) = '7f1acffe-1a33-4df6-8ff3-4ee66cf6990d'::uuid
    and now() < timestamptz '2026-11-23 06:43:23+00'
    and bucket_id = 'mina-media'
    and name in (
        '1614d308-7cbd-41b5-937f-a16f4614d095/night-journal/ivy-portrait-2.jpg',
        '5cf153f2-27c1-4976-ad74-f0dff4cf0667/night-journal/bea-portrait-2.jpg',
        'c8f76174-78a4-4943-88cb-5c2665679cdb/night-journal/wren-portrait-2.jpg',
        'a0d003a1-820b-424b-8e54-77869ea43c38/night-journal/june-portrait-2.jpg',
        '2fee4254-368a-4b4e-b62b-3c9a65c043b5/night-journal/clea-portrait-2.jpg',
        '924e6b2d-4130-4018-aea4-6e6dd8f99aa1/night-journal/nell-portrait-2.jpg',
        '3c39c22c-45b2-4525-8f9e-a27cff669033/night-journal/iris-portrait-2.jpg',
        'bec894d3-db49-4419-9fb3-6ee50d094046/night-journal/thea-portrait-2.jpg'
    )
);
